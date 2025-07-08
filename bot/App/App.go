package App

import (
	"context"
	"fmt"
	"fraktal/mev-bot-v2/Cache"
	"fraktal/mev-bot-v2/Database"
	"fraktal/mev-bot-v2/Discovery"
	"fraktal/mev-bot-v2/EventRouter"
	"fraktal/mev-bot-v2/Market"
	"fraktal/mev-bot-v2/Multicall"
	"fraktal/mev-bot-v2/Parser"
	"fraktal/mev-bot-v2/Pricing"
	"fraktal/mev-bot-v2/Subscriber"
	"fraktal/mev-bot-v2/uniswap"
	"log"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

// App is the central orchestrator, responsible for wiring services together and starting them.
type App struct {
	EthClient   *ethclient.Client
	Logs        chan types.Log
	EventRouter *EventRouter.Service
}

// NewApp initializes the application and all its constituent services.
// CORRECTED: Accepts the DBWriter service.
func NewApp(
	ethClient *ethclient.Client,
	cache *Cache.Service,
	marketService *Market.Service,
	discoveryService *Discovery.Service,
	eventRouter *EventRouter.Service,
	dbWriter *Database.DBWriter, // Added DBWriter
) (*App, error) {

	// Load initial data into the cache from the DB.
	// CORRECTED: Pass the DBWriter and MulticallService correctly.
	loadAndCacheFromDB(dbWriter, discoveryService.MulticallService, cache)

	app := &App{
		EthClient:   ethClient,
		Logs:        make(chan types.Log, 1000),
		EventRouter: eventRouter,
	}
	return app, nil
}

// Run starts the main event subscription and processing loop.
func (app *App) Run() {
	fmt.Println("Scanner App running...")
	// Subscribe to Swap events from both V2 and V3 pools.
	topics := []common.Hash{Parser.V2ABI.Events["Swap"].ID, Parser.V3ABI.Events["Swap"].ID}
	sub, err := Subscriber.Subscription(app.EthClient, app.Logs, topics)
	if err != nil {
		log.Fatalf("Subscription failed: %v", err)
	}
	fmt.Println("Subscription active. Waiting for swaps...")

	// Goroutine to handle subscription errors.
	go func() {
		for err := range sub.Err() {
			log.Fatalf("Subscription error: %v", err)
		}
	}()

	// Main event loop: pass all incoming logs to the EventRouter.
	for vLog := range app.Logs {
		go app.EventRouter.HandleLog(vLog)
	}
}

// loadAndCacheFromDB populates the cache with data from the database on startup.
// CORRECTED: Accepts the DBWriter service.
func loadAndCacheFromDB(dbWriter *Database.DBWriter, mcService *Multicall.MulticallService, cache *Cache.Service) {
	pools, tokens, err := dbWriter.LoadInitialData()
	if err != nil {
		log.Fatalf("Failed to load initial data from DB: %v", err)
	}

	// Pre-populate the token metadata cache from the database records.
	for _, token := range tokens {
		mcService.CacheTokenMetadata(token.Address, token.Symbol, token.Decimals)
	}

	var poolsToUpdate []*Cache.PoolState
	tempStateMap := make(map[common.Address]*Cache.PoolState)

	cache.Lock.Lock()
	for _, pool := range pools {
		poolAddr := common.HexToAddress(pool.Address)
		factoryAddr := common.HexToAddress(pool.Factory)
		token0Addr := common.HexToAddress(pool.Token0Address)
		token1Addr := common.HexToAddress(pool.Token1Address)

		// Get token metadata from the multicall service's cache.
		metadata := mcService.GetTokenMetadataBatch([]common.Address{token0Addr, token1Addr})
		meta0 := metadata[strings.ToLower(token0Addr.Hex())]
		meta1 := metadata[strings.ToLower(token1Addr.Hex())]

		// Create the initial PoolState struct.
		newState := &Cache.PoolState{
			Address:        poolAddr,
			Factory:        factoryAddr,
			Protocol:       uniswap.ProtocolVersion(pool.Protocol),
			IsV3Style:      strings.Contains(pool.Protocol, "V3") || strings.Contains(pool.Protocol, "Algebra"),
			SymbolTicker:   pool.SymbolTicker,
			Fee:            new(big.Float).SetFloat64(pool.Fee),
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

		// Populate the cache maps.
		cache.TickerToPools[pool.AddressTicker] = append(cache.TickerToPools[pool.AddressTicker], newState)
		cache.PoolToTicker[poolAddr] = pool.AddressTicker
		poolsToUpdate = append(poolsToUpdate, newState)
		tempStateMap[poolAddr] = newState
	}
	cache.Lock.Unlock()

	// Batch fetch initial reserves and state for all loaded pools.
	if len(poolsToUpdate) > 0 {
		log.Printf("Fetching initial state for %d pools from database...", len(poolsToUpdate))
		reserves, err := mcService.FetchPoolReservesBatch(context.Background(), poolsToUpdate)
		if err != nil {
			log.Printf("Warning: Failed to fetch some initial reserves: %v", err)
		}
		for addr, res := range reserves {
			if state, ok := tempStateMap[addr]; ok {
				state.Reserve0.Set(res.Reserve0)
				state.Reserve1.Set(res.Reserve1)
				// If it's a V3-style pool, fetch additional state like liquidity and tick.
				if state.IsV3Style {
					_, _, sqrtPrice, tick, liquidity, _ := mcService.FetchV3PoolState(addr)
					if liquidity != nil {
						state.Liquidity.Set(liquidity)
						state.SqrtPriceX96.Set(sqrtPrice)
						state.Tick.Set(tick)
					}
				}
				// Calculate and cache the initial pool price.
				state.PoolPrice.Set(Pricing.CalculatePriceFromState(state))
			}
		}
	}

	log.Printf("Loaded %d pools and %d tokens from database into cache.", len(pools), len(tokens))
}
