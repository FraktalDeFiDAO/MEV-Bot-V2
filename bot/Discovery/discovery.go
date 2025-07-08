package Discovery

import (
	"context"
	"fmt"
	"fraktal/mev-bot-v2/Cache"
	"fraktal/mev-bot-v2/Database"
	"fraktal/mev-bot-v2/Market"
	"fraktal/mev-bot-v2/Multicall"
	"fraktal/mev-bot-v2/Pricing"
	"fraktal/mev-bot-v2/config"
	"fraktal/mev-bot-v2/contracts/bindings/pooltypechecker"
	"fraktal/mev-bot-v2/uniswap"
	"log"
	"math/big"
	"os"
	"strings"
	"sync"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

// Service handles the discovery of new liquidity pools.
type Service struct {
	EthClient         *ethclient.Client
	PoolTypeChecker   *pooltypechecker.PoolTypeChecker
	MulticallService  *Multicall.MulticallService
	Cache             *Cache.Service
	MarketService     *Market.Service
	DiscoveryQueue    chan common.Address
	DBWriteQueue      chan<- *Database.DBWriteRequest // CORRECTED: Use the DB writer channel
	failedDiscoveries map[common.Address]bool
	failedLock        sync.RWMutex
	failedLog         *log.Logger
}

// NewService initializes the discovery service.
func NewService(
	cfg *config.Config,
	ethClient *ethclient.Client,
	mcService *Multicall.MulticallService,
	cache *Cache.Service,
	marketService *Market.Service,
	queue chan common.Address,
	dbWriteQueue chan<- *Database.DBWriteRequest, // CORRECTED: Accept the channel
) (*Service, error) {
	failedLogFile, err := os.OpenFile("failed_discoveries.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
	if err != nil {
		return nil, fmt.Errorf("could not open failed discoveries log file: %w", err)
	}
	failedLogger := log.New(failedLogFile, "FAILURE: ", log.LstdFlags)

	checkerAddr := common.HexToAddress(cfg.PoolTypeCheckerAddress)
	if checkerAddr == (common.Address{}) {
		return nil, fmt.Errorf("POOL_TYPE_CHECKER_ADDRESS not configured")
	}
	checker, err := pooltypechecker.NewPoolTypeChecker(checkerAddr, ethClient)
	if err != nil {
		return nil, fmt.Errorf("failed to instantiate PoolTypeChecker: %w", err)
	}

	return &Service{
		EthClient:         ethClient,
		PoolTypeChecker:   checker,
		MulticallService:  mcService,
		Cache:             cache,
		MarketService:     marketService,
		DiscoveryQueue:    queue,
		DBWriteQueue:      dbWriteQueue,
		failedDiscoveries: make(map[common.Address]bool),
		failedLog:         failedLogger,
	}, nil
}

// Run starts the discovery service's main loop.
func (s *Service) Run() {
	log.Println("Discovery Service running...")
	for poolAddress := range s.DiscoveryQueue {
		go s.processDiscovery(poolAddress)
	}
}

// processDiscovery handles the discovery logic for a single pool address.
func (s *Service) processDiscovery(poolAddress common.Address) {
	s.failedLock.RLock()
	if s.failedDiscoveries[poolAddress] {
		s.failedLock.RUnlock()
		return
	}
	s.failedLock.RUnlock()

	s.Cache.Lock.RLock()
	_, isKnown := s.Cache.PoolToTicker[poolAddress]
	s.Cache.Lock.RUnlock()
	if isKnown {
		return
	}

	log.Printf("Discovery: Checking new address %s with on-chain PoolTypeChecker...", poolAddress.Hex())

	poolType, err := s.PoolTypeChecker.CheckPoolType(&bind.CallOpts{}, poolAddress)
	if err != nil {
		if strings.Contains(err.Error(), "execution reverted") {
			log.Printf("Discovery: Address %s is not a compatible pool. Ignoring.", poolAddress.Hex())
		} else {
			s.logAndCacheFailure(poolAddress, fmt.Errorf("PoolTypeChecker contract call failed: %w", err))
		}
		s.MarketService.CleanupPendingLogs(poolAddress)
		return
	}

	if poolType == uniswap.PoolTypeNONE {
		log.Printf("Discovery: Address %s is not a supported pool type (Type: NONE). Ignoring.", poolAddress.Hex())
		s.MarketService.CleanupPendingLogs(poolAddress)
		return
	}

	_, err = s.discoverAndCachePool(poolAddress, poolType)
	if err != nil {
		s.logAndCacheFailure(poolAddress, fmt.Errorf("data fetching failed for identified pool type %d: %w", poolType, err))
		s.MarketService.CleanupPendingLogs(poolAddress)
		return
	}

	s.MarketService.ProcessPendingLogs(poolAddress)
}

// discoverAndCachePool fetches all necessary data for a new pool and adds it to the cache.
func (s *Service) discoverAndCachePool(poolAddress common.Address, poolType uint8) (*Cache.PoolState, error) {
	var token0Addr, token1Addr, factoryAddr common.Address
	var fee *big.Int = big.NewInt(0)
	var protocol uniswap.ProtocolVersion
	var isV3Style bool
	var err error

	if poolType == uniswap.PoolTypeUNISWAPV2 {
		protocol = uniswap.V2
		isV3Style = false
		token0Addr, token1Addr, factoryAddr, err = s.MulticallService.FetchV2PairData(poolAddress)
		fee.SetInt64(3000)
	} else {
		isV3Style = true
		token0Addr, token1Addr, factoryAddr, err = s.MulticallService.FetchV3StyleTokensAndFactory(poolAddress)
	}
	if err != nil {
		return nil, err
	}

	switch poolType {
	case uniswap.PoolTypeUNISWAPV3:
		protocol = uniswap.V3
		fee, err = s.MulticallService.FetchV3PoolFee(poolAddress)
	case uniswap.PoolTypeALGEBRAV1:
		protocol = uniswap.AlgebraV1
		fee, err = s.MulticallService.FetchV3PoolFee(poolAddress)
	case uniswap.PoolTypeALGEBRAV1ADAPTIVE:
		protocol = uniswap.AlgebraV1_Adaptive
	case uniswap.PoolTypeALGEBRAV1DBF:
		protocol = uniswap.AlgebraV1_DBF
	case uniswap.PoolTypeALGEBRAV2DBF:
		protocol = uniswap.AlgebraV2_DBF
	}
	if err != nil {
		return nil, err
	}

	metadata := s.MulticallService.GetTokenMetadataBatch([]common.Address{token0Addr, token1Addr})
	meta0 := metadata[strings.ToLower(token0Addr.Hex())]
	meta1 := metadata[strings.ToLower(token1Addr.Hex())]

	addrTicker, symTicker, isReversed := generateTickers(token0Addr, token1Addr, meta0.Symbol, meta1.Symbol)
	feeF := new(big.Float).SetInt(fee)
	feePercent := new(big.Float).Quo(feeF, big.NewFloat(1000000))

	newState := &Cache.PoolState{
		Address:        poolAddress,
		Factory:        factoryAddr,
		Protocol:       protocol,
		IsV3Style:      isV3Style,
		IsReversed:     isReversed, // Set the reversal flag
		Fee:            feePercent,
		SymbolTicker:   symTicker,
		PoolPrice:      new(big.Float),
		Reserve0:       new(big.Int),
		Reserve1:       new(big.Int),
		Liquidity:      new(big.Int),
		SqrtPriceX96:   new(big.Int),
		Tick:           new(big.Int),
		Token0:         token0Addr,
		Token1:         token1Addr,
		Token0Decimals: meta0.Decimals,
		Token1Decimals: meta1.Decimals,
		Token0Symbol:   meta0.Symbol,
		Token1Symbol:   meta1.Symbol,
	}

	reserves, resErr := s.MulticallService.FetchPoolReservesBatch(context.Background(), []*Cache.PoolState{newState})
	if resErr != nil {
		return nil, resErr
	}
	if r, ok := reserves[poolAddress]; ok {
		newState.Reserve0.Set(r.Reserve0)
		newState.Reserve1.Set(r.Reserve1)
		if isV3Style {
			_, _, sqrtPrice, tick, liquidity, _ := s.MulticallService.FetchV3PoolState(poolAddress)
			if liquidity != nil {
				newState.Liquidity.Set(liquidity)
				newState.SqrtPriceX96.Set(sqrtPrice)
				newState.Tick.Set(tick)
			}
		}
	}

	newState.PoolPrice.Set(Pricing.CalculatePriceFromState(newState))

	s.Cache.Lock.Lock()
	s.Cache.TickerToPools[addrTicker] = append(s.Cache.TickerToPools[addrTicker], newState)
	s.Cache.PoolToTicker[poolAddress] = addrTicker
	s.Cache.Lock.Unlock()

	// CORRECTED: Send write requests to the DB writer channel instead of calling DB directly.
	s.DBWriteQueue <- &Database.DBWriteRequest{
		Type: Database.SaveTokenRequest,
		Token: &Database.TokenRecord{
			Address:  token0Addr.Hex(),
			Symbol:   meta0.Symbol,
			Decimals: meta0.Decimals,
		},
	}
	s.DBWriteQueue <- &Database.DBWriteRequest{
		Type: Database.SaveTokenRequest,
		Token: &Database.TokenRecord{
			Address:  token1Addr.Hex(),
			Symbol:   meta1.Symbol,
			Decimals: meta1.Decimals,
		},
	}
	feeF64, _ := feePercent.Float64()
	s.DBWriteQueue <- &Database.DBWriteRequest{
		Type: Database.SavePoolRequest,
		Pool: &Database.PoolRecord{
			Address:       poolAddress.Hex(),
			Protocol:      string(protocol),
			Factory:       factoryAddr.Hex(),
			Fee:           feeF64,
			AddressTicker: addrTicker,
			SymbolTicker:  symTicker,
			Token0Address: token0Addr.Hex(),
			Token1Address: token1Addr.Hex(),
		},
	}

	log.Printf("Discovery: Successfully discovered and cached %s pool %s", protocol, poolAddress.Hex())
	return newState, nil
}

// logAndCacheFailure logs a failed discovery attempt and adds the address to a failure cache.
func (s *Service) logAndCacheFailure(address common.Address, err error) {
	s.failedLock.Lock()
	defer s.failedLock.Unlock()
	if !s.failedDiscoveries[address] {
		log.Printf("Discovery: Failed to process pool %s. See failed_discoveries.log for details.", address.Hex())
		s.failedLog.Printf("Address: %s | Error: %v\n", address.Hex(), err)
		s.failedDiscoveries[address] = true
	}
}

// generateTickers creates canonical address and symbol tickers for a token pair.
func generateTickers(addr0, addr1 common.Address, sym0, sym1 string) (string, string, bool) {
	addrStr0, addrStr1 := strings.ToLower(addr0.Hex()), strings.ToLower(addr1.Hex())
	isReversed := addrStr0 > addrStr1
	if isReversed {
		addrStr0, addrStr1 = addrStr1, addrStr0
		sym0, sym1 = sym1, sym0
	}
	return fmt.Sprintf("%s_%s", addrStr0, addrStr1), fmt.Sprintf("%s_%s", sym0, sym1), isReversed
}
