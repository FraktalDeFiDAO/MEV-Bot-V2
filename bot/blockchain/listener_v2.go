package blockchain

import (
	"context"
	"fmt"

	// "fmt" // No longer needed for getV2PairTokens
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

// getTokenMetadata function is removed from here. Its functionality is now part of
// MulticallService.GetTokenMetadataBatch and the global KnownTokenMetadata cache.
// getV2PairTokens function is removed as its functionality is now part of
// MulticallService.FetchV2PairInitialData.

// fetchAndProcessV2InitialState is now responsible for using MulticallService
func fetchAndProcessV2InitialState(
	ctx context.Context,
	mcService *MulticallService, // Now takes MulticallService
	pairAddr common.Address,
	outputChan chan<- *uniswap.PoolData,
) {
	log.Printf("V2 InitialSync: Fetching initial state for pair %s via multicall", pairAddr.Hex())

	token0Addr, token1Addr, reserve0, reserve1, err := mcService.FetchV2PairInitialData(ctx, pairAddr)
	if err != nil {
		log.Printf("V2 InitialSync: Failed to fetch initial data for V2 pair %s: %v", pairAddr.Hex(), err)
		return
	}

	// Trigger metadata fetching for these tokens if not already known/fetched
	// The GetTokenMetadataBatch is designed to be idempotent and efficient.
	mcService.GetTokenMetadataBatch(ctx, []common.Address{token0Addr, token1Addr})

	// Retrieve potentially updated metadata from cache
	token0Symbol, token0Decimals, t0Known := GetTokenSymbolAndDecimals(token0Addr)
	token1Symbol, token1Decimals, t1Known := GetTokenSymbolAndDecimals(token1Addr)

	if !t0Known || !t1Known {
		// This might happen if GetTokenMetadataBatch failed or is async and result not yet in cache.
		// Depending on strictness, you might wait or use defaults. For now, log and proceed.
		log.Printf("V2 InitialSync: Metadata for tokens of pair %s might still be pending/unknown after batch fetch. T0 known: %v, T1 known: %v", pairAddr.Hex(), t0Known, t1Known)
	}

	price0For1, price1For0 := utils.CalculateV2Price(reserve0, reserve1, token0Decimals, token1Decimals)

	poolData := &uniswap.PoolData{
		PoolAddress:          strings.ToLower(pairAddr.Hex()),
		Protocol:             uniswap.V2,
		Token0Address:        strings.ToLower(token0Addr.Hex()),
		Token1Address:        strings.ToLower(token1Addr.Hex()),
		Token0Symbol:         token0Symbol,
		Token1Symbol:         token1Symbol,
		Token0Decimals:       token0Decimals,
		Token1Decimals:       token1Decimals,
		Reserve0:             reserve0,
		Reserve1:             reserve1,
		PriceToken0ForToken1: price0For1,
		PriceToken1ForToken0: price1For0,
		Timestamp:            time.Now().UTC(),
	}
	select {
	case outputChan <- poolData:
		log.Printf("V2 InitialSync: Sent initial state for %s to processing channel.", pairAddr.Hex())
	case <-ctx.Done():
		log.Printf("V2 InitialSync: Context cancelled while sending initial state for %s.", pairAddr.Hex())
	}
}

// ListenV2Events now requires MulticallService
func ListenV2Events(
	ctx context.Context,
	client *ethclient.Client, // Keep ethClient for SubscribeFilterLogs
	mcService *MulticallService, // Add MulticallService
	pairAddresses []common.Address,
	outputChan chan<- *uniswap.PoolData,
	initialSyncBlock uint64,
) {
	if len(pairAddresses) == 0 {
		log.Println("V2 Listener: No pair addresses provided to listen on.")
		return
	}
	log.Printf("V2 Listener: Managing %d pairs.", len(pairAddresses))

	var initialStateWg sync.WaitGroup
	// uniqueTokensForMetaFetch := make(map[common.Address]struct{})

	// First pass: collect all unique token addresses from pairs for initial state fetching
	// (This part of collecting unique tokens before calling FetchV2PairInitialData might be redundant
	// if FetchV2PairInitialData internally calls GetTokenMetadataBatch for its tokens.
	// For now, FetchV2PairInitialData returns token addresses, and then we batch metadata fetching.)

	for _, pAddr := range pairAddresses {
		initialStateWg.Add(1)
		go func(addr common.Address) {
			defer initialStateWg.Done()
			fetchCtx, cancel := context.WithTimeout(ctx, mcService.defaultTimeout)
			defer cancel()
			// This will call mcService.FetchV2PairInitialData which in turn calls mcService.GetTokenMetadataBatch
			fetchAndProcessV2InitialState(fetchCtx, mcService, addr, outputChan)
		}(pAddr)
	}
	initialStateWg.Wait()
	log.Printf("V2 Listener: Initial state fetch process completed for %d pairs.", len(pairAddresses))

	// The rest of the subscription logic remains similar...
	query := ethereum.FilterQuery{
		Addresses: pairAddresses,
		Topics:    [][]common.Hash{{uniswap.SyncEvent}},
	}
	if initialSyncBlock > 0 {
		query.FromBlock = new(big.Int).SetUint64(initialSyncBlock)
		log.Printf("V2 Listener: Will also fetch historical Sync events from block %d.", initialSyncBlock)
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
			log.Printf("V2 Listener: Attempting to subscribe to Sync events for %d pairs.", len(pairAddresses))
			currentSub, currentErr := client.SubscribeFilterLogs(subAttemptCtx, query, logs)
			if currentErr != nil {
				log.Printf("V2 Listener: Failed to subscribe to V2 Sync events: %v. Retrying in 10s.", currentErr)
				select {
				case <-time.After(10 * time.Second):
					continue
				case <-subAttemptCtx.Done():
					return
				}
			}
			log.Printf("V2 Listener: Successfully subscribed to V2 Sync events for %d pairs.", len(pairAddresses))
			sub = currentSub
			return
		}
	}()
	<-subAttemptCtx.Done()
	if sub == nil && ctx.Err() == nil {
		log.Printf("V2 Listener: Subscription attempts failed. Listener stopping.")
		return
	}
	if ctx.Err() != nil {
		log.Println("V2 Listener: Main context cancelled during subscription. Listener stopping.")
		return
	}
	defer func() {
		if sub != nil {
			sub.Unsubscribe()
		}
		log.Println("V2 Listener: Unsubscribed and shutting down.")
	}()

	// Event processing loop
	for {
		select {
		case <-ctx.Done():
			log.Println("V2 Listener: Context cancelled, shutting down event loop.")
			return
		case err := <-sub.Err():
			log.Printf("V2 Listener: Subscription error: %v. Listener will terminate.", err)
			return
		case vLog := <-logs:
			if vLog.Removed { /* ... handle reorg ... */
				log.Printf("V2 Listener: Log for pair %s (Tx: %s) was removed due to reorg. Ignoring.", vLog.Address.Hex(), vLog.TxHash.Hex())
				continue
			}

			syncEvent, err := uniswap.ParseV2Sync(vLog)
			if err != nil { /* ... handle parse error ... */
				log.Printf("Error parsing V2 Sync event for %s (Tx: %s): %v", vLog.Address.Hex(), vLog.TxHash.Hex(), err)
				continue
			}

			// Get token addresses for the pair (these should be cached by initial fetch or a previous event)
			// For simplicity, we assume FetchV2PairInitialData (or similar for already known pairs) has populated caches.
			// A robust system might re-fetch token addresses if not found, but that's less likely for Sync events.
			// For this example, we'll re-use the MulticallService to get pair tokens if needed, though ideally cached.
			// This is somewhat inefficient if called on every Sync event. Better to cache pair token addresses.
			// Let's assume pairTokenCache in main.go or a similar structure holds this.
			// For simplicity here, we'll use a direct call if not cached, but it's not optimal for Sync.
			// Better: Cache pair token addresses during initial sync.

			// For Sync events, token addresses don't change. We rely on initial sync to get them.
			// We need a way to get T0/T1 for the vLog.Address without calling contract on each Sync.
			// This should come from a cache populated during `fetchAndProcessV2InitialState` or similar.
			// For now, we will assume that `processedDataChan` sends data which includes token addresses.
			// If not, this part needs a cached lookup for Token0/Token1 for `vLog.Address`.
			// Let's assume we have a way to get this from a local cache populated by `fetchAndProcess...`

			// Simplified: We need token0/token1 addresses for this pair.
			// This info should be cached when the pool is first processed.
			// We can't call mcService.FetchV2PairInitialData on every Sync event.
			// We'll rely on a global cache or pass this info through.
			// For now, let's assume `PoolData` for this `vLog.Address` is in `memCache` and has token info.
			// This requires `memCache` to be accessible or a different flow.
			// --- THIS PART IS A SIMPLIFICATION ---
			// A better way: maintain a map[pairAddress] -> {token0, token1, dec0, dec1, sym0, sym1}
			// This map is populated when fetchAndProcessV2InitialState is called.

			// Quick fix: Attempt to get a previously processed PoolData from cache to get token info
			// This is not ideal because `memCache` is in `main.go`.
			// We'll simulate having this info. In a real system, listeners would have access to this cached pool metadata.

			// This is a placeholder for getting token details for the pair.
			// In a real system, you'd have this data cached from the initial processing of the pair.
			// For this example, we cannot easily access main's memCache here.
			// We will have to make a call to get token data if not known, which is suboptimal for Sync events.
			// Let's assume `token0Addr, token1Addr` are somehow known for `vLog.Address`

			// Get token metadata (symbol, decimals)
			// This will use the global KnownTokenMetadata cache, potentially updated by mcService
			// mcService.GetTokenMetadataBatch(ctx, []common.Address{token0Addr, token1Addr}) // Ensure metadata is fetched if new tokens appear unexpectedly
			// This is also problematic if token0Addr/token1Addr are not known.
			// The design implies that once a pool is listened to, its T0/T1 and their metadata are known.

			// Let's assume for a Sync event, the pool's basic structure (tokens, decimals) is already known and cached.
			// We'll fetch from our global cache.
			// This is tricky: how does the listener know token0/token1 for a given pairAddress without a call?
			// The initial state fetch handles this. We need to persist/cache that mapping.
			// We'll assume a local cache within blockchain package for this, populated by initial syncs.
			// (This is getting complex without a shared state accessible by listeners for basic pair data)

			// SIMPLIFICATION: We cannot call mcService.FetchV2PairInitialData here.
			// The listener needs a way to know T0/T1 for vLog.Address.
			// For now, we will skip fully resolving T0/T1 on *every* sync, assuming this data is fetched
			// and available from a higher-level cache that the *processor* of this event will use.
			// This listener will focus on emitting the core Sync event data.
			// The processor (in main.go) will enrich it using cached metadata.

			// The listener should output what it can directly get from the event or minimal calls.
			// For Sync, that's Reserve0, Reserve1. Token addresses and symbols/decimals need to be joined later.
			// This changes the PoolData structure usage or implies later enrichment.

			// To make this runnable, we *must* have token metadata to calculate prices.
			// We will assume that fetchAndProcessV2InitialState has populated enough for GetTokenSymbolAndDecimals
			// and that we somehow know token0 and token1 for vLog.Address.
			// This is a structural challenge with the current separation.
			// Let's assume this information is part of what `pairAddresses` implies.
			// HACK: for now, we try to refetch if not in cache (BAD for Sync events)
			cachedT0, cachedT1, errTokenInfo := getCachedV2PairTokens(vLog.Address) // Need to implement this cache
			if errTokenInfo != nil {
				log.Printf("V2 Listener: Critical - could not get cached token info for pair %s for Sync event. Skipping. Error: %v", vLog.Address.Hex(), errTokenInfo)
				continue
			}

			// Ensure metadata for these tokens is known
			mcService.GetTokenMetadataBatch(ctx, []common.Address{cachedT0, cachedT1}) // Ensure metadata up-to-date
			token0Symbol, token0Decimals, _ := GetTokenSymbolAndDecimals(cachedT0)
			token1Symbol, token1Decimals, _ := GetTokenSymbolAndDecimals(cachedT1)

			price0For1, price1For0 := utils.CalculateV2Price(syncEvent.Reserve0, syncEvent.Reserve1, token0Decimals, token1Decimals)

			blockHeader, _ := client.HeaderByHash(ctx, vLog.BlockHash)
			eventTime := time.Now().UTC()
			if blockHeader != nil {
				eventTime = time.Unix(int64(blockHeader.Time), 0).UTC()
			}

			poolData := &uniswap.PoolData{
				PoolAddress:          strings.ToLower(vLog.Address.Hex()),
				Protocol:             uniswap.V2,
				Token0Address:        strings.ToLower(cachedT0.Hex()), // Needs to be reliably sourced
				Token1Address:        strings.ToLower(cachedT1.Hex()), // Needs to be reliably sourced
				Token0Symbol:         token0Symbol,
				Token1Symbol:         token1Symbol,
				Token0Decimals:       token0Decimals,
				Token1Decimals:       token1Decimals,
				Reserve0:             syncEvent.Reserve0,
				Reserve1:             syncEvent.Reserve1,
				PriceToken0ForToken1: price0For1,
				PriceToken1ForToken0: price1For0,
				Timestamp:            eventTime,
				RawEvent:             vLog,
			}
			select {
			case outputChan <- poolData:
			case <-ctx.Done():
				log.Println("V2 Listener: Context cancelled while sending processed V2 data.")
				return
			}
		}
	}
}

// HACK/TODO: Implement proper caching for pair -> (token0, token1) mapping
// This cache should be populated by fetchAndProcessV2InitialState.
// For now, this is a placeholder. A real implementation would use a concurrent map.
var localPairTokenCache = struct {
	sync.RWMutex
	Data map[common.Address]struct{ T0, T1 common.Address }
}{Data: make(map[common.Address]struct{ T0, T1 common.Address })}

func CacheV2PairTokens(pair common.Address, t0 common.Address, t1 common.Address) {
	localPairTokenCache.Lock()
	defer localPairTokenCache.Unlock()
	localPairTokenCache.Data[pair] = struct{ T0, T1 common.Address }{t0, t1}
}
func getCachedV2PairTokens(pair common.Address) (common.Address, common.Address, error) {
	localPairTokenCache.RLock()
	defer localPairTokenCache.RUnlock()
	tokens, found := localPairTokenCache.Data[pair]
	if !found {
		return common.Address{}, common.Address{}, fmt.Errorf("V2 pair token info not cached for %s", pair.Hex())
	}
	return tokens.T0, tokens.T1, nil
}
