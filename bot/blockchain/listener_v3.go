package blockchain

import (
	"context"
	"fmt"
	// "fmt" // No longer used for getV3PoolMetadata
	"log"
	"math/big"
	"strings"
	"sync"
	"time"

	"fraktal/mev-bot-v2/uniswap" // Adjusted
	"fraktal/mev-bot-v2/utils"   // Adjusted

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

// getV3PoolMetadata function removed, functionality integrated into FetchV3PoolInitialData via multicall.

func fetchAndProcessV3InitialState(
	ctx context.Context,
	mcService *MulticallService, // Now takes MulticallService
	poolAddr common.Address,
	outputChan chan<- *uniswap.PoolData,
) {
	log.Printf("V3 InitialSync: Fetching initial state for pool %s via multicall", poolAddr.Hex())

	token0Addr, token1Addr, sqrtPriceX96, tick, liquidity, err := mcService.FetchV3PoolInitialData(ctx, poolAddr)
	if err != nil {
		log.Printf("V3 InitialSync: Failed to fetch initial data for V3 pool %s: %v", poolAddr.Hex(), err)
		return
	}

	mcService.GetTokenMetadataBatch(ctx, []common.Address{token0Addr, token1Addr})
	token0Symbol, token0Decimals, t0Known := GetTokenSymbolAndDecimals(token0Addr)
	token1Symbol, token1Decimals, t1Known := GetTokenSymbolAndDecimals(token1Addr)

	if !t0Known || !t1Known {
		log.Printf("V3 InitialSync: Metadata for tokens of pool %s might still be pending/unknown. T0 known: %v, T1 known: %v", poolAddr.Hex(), t0Known, t1Known)
	}

	// Add to V3 local cache too, similar to V2
	if err == nil {
		CacheV3PoolTokens(poolAddr, token0Addr, token1Addr)
	}

	price0For1, price1For0 := utils.CalculateV3Price(sqrtPriceX96, token0Decimals, token1Decimals)

	poolData := &uniswap.PoolData{
		PoolAddress:          strings.ToLower(poolAddr.Hex()),
		Protocol:             uniswap.V3,
		Token0Address:        strings.ToLower(token0Addr.Hex()),
		Token1Address:        strings.ToLower(token1Addr.Hex()),
		Token0Symbol:         token0Symbol,
		Token1Symbol:         token1Symbol,
		Token0Decimals:       token0Decimals,
		Token1Decimals:       token1Decimals,
		SqrtPriceX96:         sqrtPriceX96,
		Liquidity:            liquidity,
		Tick:                 tick,
		PriceToken0ForToken1: price0For1,
		PriceToken1ForToken0: price1For0,
		Timestamp:            time.Now().UTC(),
	}
	select {
	case outputChan <- poolData:
		log.Printf("V3 InitialSync: Sent initial state for %s to processing channel.", poolAddr.Hex())
	case <-ctx.Done():
		log.Printf("V3 InitialSync: Context cancelled while sending initial state for %s.", poolAddr.Hex())
	}
}

// ListenV3Events now requires MulticallService
func ListenV3Events(
	ctx context.Context,
	client *ethclient.Client, // Keep for SubscribeFilterLogs
	mcService *MulticallService, // Add MulticallService
	poolAddresses []common.Address,
	outputChan chan<- *uniswap.PoolData,
	initialSyncBlock uint64,
) {
	if len(poolAddresses) == 0 {
		log.Println("V3 Listener: No pool addresses provided.")
		return
	}
	log.Printf("V3 Listener: Managing %d pools.", len(poolAddresses))

	var initialStateWg sync.WaitGroup
	for _, pAddr := range poolAddresses {
		initialStateWg.Add(1)
		go func(addr common.Address) {
			defer initialStateWg.Done()
			fetchCtx, cancel := context.WithTimeout(ctx, mcService.defaultTimeout)
			defer cancel()
			fetchAndProcessV3InitialState(fetchCtx, mcService, addr, outputChan)
		}(pAddr)
	}
	initialStateWg.Wait()
	log.Printf("V3 Listener: Initial state fetch process completed for %d pools.", len(poolAddresses))

	// Rest of subscription logic is similar...
	query := ethereum.FilterQuery{
		Addresses: poolAddresses,
		Topics:    [][]common.Hash{{uniswap.SwapEvent}},
	}
	if initialSyncBlock > 0 {
		query.FromBlock = new(big.Int).SetUint64(initialSyncBlock)
	}

	logs := make(chan types.Log, 100)
	subAttemptCtx, subAttemptCancel := context.WithCancel(ctx)
	var sub ethereum.Subscription
	go func() {
		defer subAttemptCancel()
		for { /* ... subscription retry logic ... */
			select {
			case <-subAttemptCtx.Done():
				return
			default:
			}
			log.Printf("V3 Listener: Attempting to subscribe to Swap for %d pools.", len(poolAddresses))
			currentSub, currentErr := client.SubscribeFilterLogs(subAttemptCtx, query, logs)
			if currentErr != nil {
				log.Printf("V3 Listener: Failed to subscribe to V3 Swap: %v. Retrying.", currentErr)
				select {
				case <-time.After(10 * time.Second):
					continue
				case <-subAttemptCtx.Done():
					return
				}
			}
			log.Printf("V3 Listener: Successfully subscribed to V3 Swap for %d pools.", len(poolAddresses))
			sub = currentSub
			return
		}
	}()
	<-subAttemptCtx.Done()
	if sub == nil && ctx.Err() == nil {
		log.Println("V3 Listener: Sub attempts failed.")
		return
	}
	if ctx.Err() != nil {
		log.Println("V3 Listener: Ctx cancelled during sub.")
		return
	}
	defer func() {
		if sub != nil {
			sub.Unsubscribe()
		}
		log.Println("V3 Listener: Unsubscribed and shutting down.")
	}()

	// Event processing loop
	for {
		select {
		case <-ctx.Done():
			log.Println("V3 Listener: Context cancelled, shutting down event loop.")
			return
		case err := <-sub.Err():
			log.Printf("V3 Listener: Subscription error: %v. Listener will terminate.", err)
			return
		case vLog := <-logs:
			if vLog.Removed { /* ... handle reorg ... */
				log.Printf("V3 Listener: Log for pool %s (Tx: %s) removed. Ignoring.", vLog.Address.Hex(), vLog.TxHash.Hex())
				continue
			}

			swapEvent, err := uniswap.ParseV3Swap(vLog)
			if err != nil { /* ... handle parse error ... */
				log.Printf("Error parsing V3 Swap for %s (Tx: %s): %v", vLog.Address.Hex(), vLog.TxHash.Hex(), err)
				continue
			}

			// Similar to V2, we need cached T0/T1 info for this pool.
			cachedT0, cachedT1, errTokenInfo := getCachedV3PoolTokens(vLog.Address) // Need to implement this cache
			if errTokenInfo != nil {
				log.Printf("V3 Listener: Critical - could not get cached token info for pool %s for Swap event. Skipping. Error: %v", vLog.Address.Hex(), errTokenInfo)
				continue
			}

			mcService.GetTokenMetadataBatch(ctx, []common.Address{cachedT0, cachedT1}) // Ensure metadata up-to-date
			token0Symbol, token0Decimals, _ := GetTokenSymbolAndDecimals(cachedT0)
			token1Symbol, token1Decimals, _ := GetTokenSymbolAndDecimals(cachedT1)

			price0For1, price1For0 := utils.CalculateV3Price(swapEvent.SqrtPriceX96, token0Decimals, token1Decimals)

			blockHeader, _ := client.HeaderByHash(ctx, vLog.BlockHash)
			eventTime := time.Now().UTC()
			if blockHeader != nil {
				eventTime = time.Unix(int64(blockHeader.Time), 0).UTC()
			}

			poolData := &uniswap.PoolData{
				PoolAddress:          strings.ToLower(vLog.Address.Hex()),
				Protocol:             uniswap.V3,
				Token0Address:        strings.ToLower(cachedT0.Hex()), // Needs reliable source
				Token1Address:        strings.ToLower(cachedT1.Hex()), // Needs reliable source
				Token0Symbol:         token0Symbol,
				Token1Symbol:         token1Symbol,
				Token0Decimals:       token0Decimals,
				Token1Decimals:       token1Decimals,
				SqrtPriceX96:         swapEvent.SqrtPriceX96,
				Liquidity:            swapEvent.Liquidity,
				Tick:                 swapEvent.Tick,
				PriceToken0ForToken1: price0For1,
				PriceToken1ForToken0: price1For0,
				Timestamp:            eventTime,
				RawEvent:             vLog,
			}
			select {
			case outputChan <- poolData:
			case <-ctx.Done():
				log.Println("V3 Listener: Context cancelled while sending processed V3 data.")
				return
			}
		}
	}
}

// HACK/TODO: Cache for V3 Pool -> (token0, token1)
var localV3PoolTokenCache = struct {
	sync.RWMutex
	Data map[common.Address]struct{ T0, T1 common.Address }
}{Data: make(map[common.Address]struct{ T0, T1 common.Address })}

func CacheV3PoolTokens(pool common.Address, t0 common.Address, t1 common.Address) {
	localV3PoolTokenCache.Lock()
	defer localV3PoolTokenCache.Unlock()
	localV3PoolTokenCache.Data[pool] = struct{ T0, T1 common.Address }{t0, t1}
}
func getCachedV3PoolTokens(pool common.Address) (common.Address, common.Address, error) {
	localV3PoolTokenCache.RLock()
	defer localV3PoolTokenCache.RUnlock()
	tokens, found := localV3PoolTokenCache.Data[pool]
	if !found {
		return common.Address{}, common.Address{}, fmt.Errorf("V3 pool token info not cached for %s", pool.Hex())
	}
	return tokens.T0, tokens.T1, nil
}
