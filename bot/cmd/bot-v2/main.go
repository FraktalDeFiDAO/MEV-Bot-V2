package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"fraktal/mev-bot-v2/blockchain" // Adjusted
	"fraktal/mev-bot-v2/cache"      // Adjusted
	"fraktal/mev-bot-v2/config"     // Adjusted
	"fraktal/mev-bot-v2/storage"    // Adjusted
	"fraktal/mev-bot-v2/uniswap"    // Adjusted
	"fraktal/mev-bot-v2/utils"      // Adjusted

	"github.com/ethereum/go-ethereum/common"
	// "github.com/ethereum/go-ethereum/ethclient" // No longer needed here if mcService handles client
)

var (
	activeV2Pools = make(map[string]common.Address)
	activeV3Pools = make(map[string]common.Address)
	poolsMutex    sync.RWMutex

	restartV2ListenerChan = make(chan struct{}, 1)
	restartV3ListenerChan = make(chan struct{}, 1)
)

// verifyPoolWithClient is now simplified as MulticallService handles verification calls
func verifyPool(ctx context.Context, mcService *blockchain.MulticallService, poolAddr common.Address, protocol uniswap.ProtocolVersion) bool {
	return mcService.VerifyPoolWithMulticall(ctx, poolAddr, protocol)
}

func main() {
	utils.InitLogging()

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}
	log.Println("Configuration loaded.")

	ethClient, err := blockchain.Connect(cfg.ArbitrumRPCURL) // ethClient still needed for subscriptions
	if err != nil {
		log.Fatalf("Failed to connect to Arbitrum client: %v", err)
	}
	defer ethClient.Close()
	log.Println("Ethereum client connected.")

	// Initialize Multicall Service
	mcService, err := blockchain.NewMulticallService(ethClient, common.HexToAddress(cfg.MulticallAddress))
	if err != nil {
		log.Fatalf("Failed to initialize Multicall service: %v", err)
	}
	log.Println("Multicall service initialized.")

	// ... (DB, Cache, Initial active pools setup remain similar) ...
	var dbStore storage.DataStore
	switch cfg.DBType {
	case "sqlite":
		dbStore = storage.NewSQLiteStore(cfg.DBDsn)
	default:
		log.Fatalf("Unsupported DB_TYPE: %s", cfg.DBType)
	}
	if err := dbStore.Connect(); err != nil {
		log.Fatalf("DB connect error: %v", err)
	}
	defer dbStore.Close()
	if err := dbStore.Migrate(); err != nil {
		log.Fatalf("DB migrate error: %v", err)
	}
	log.Println("Database connected and migrated.")
	memCache := cache.NewMemoryCache()
	log.Println("In-memory cache initialized.")

	poolsMutex.Lock()
	for _, addrStr := range cfg.TrackedV2Pairs { /* ... */
		if common.IsHexAddress(addrStr) {
			activeV2Pools[strings.ToLower(common.HexToAddress(addrStr).Hex())] = common.HexToAddress(addrStr)
		}
	}
	for _, addrStr := range cfg.TrackedV3Pools { /* ... */
		if common.IsHexAddress(addrStr) {
			activeV3Pools[strings.ToLower(common.HexToAddress(addrStr).Hex())] = common.HexToAddress(addrStr)
		}
	}
	log.Printf("Initialized with %d manual V2 pairs and %d manual V3 pools.", len(activeV2Pools), len(activeV3Pools))
	poolsMutex.Unlock()

	processedDataChan := make(chan *uniswap.PoolData, 1024)
	dbWriteChan := make(chan *uniswap.PoolData, 1024)
	newPoolChan := make(chan *uniswap.NewPoolNotification, 256)

	ctx, cancel := context.WithCancel(context.Background())
	var wg sync.WaitGroup

	// DB Writer Goroutine (no change)
	wg.Add(1)
	go func() {
		defer wg.Done() /* ... */
		log.Println("DB Writer goroutine started.")
		for {
			select {
			case data := <-dbWriteChan:
				if data == nil {
					continue
				}
				if err := dbStore.SavePoolUpdate(data); err != nil {
					log.Printf("Error saving pool update to DB for %s: %v", data.PoolAddress, err)
				}
			case <-ctx.Done():
				log.Println("DB Writer: Draining channel and shutting down...")
				for len(dbWriteChan) > 0 {
					data := <-dbWriteChan
					if data == nil {
						continue
					}
					if err := dbStore.SavePoolUpdate(data); err != nil {
						log.Printf("Error saving during shutdown for %s: %v", data.PoolAddress, err)
					}
				}
				log.Println("DB Writer goroutine finished.")
				return
			}
		}
	}()

	// Cache Updater and Forwarder to DB Goroutine (no change)
	wg.Add(1)
	go func() {
		defer wg.Done() /* ... */
		log.Println("Cache Updater/DB Forwarder goroutine started.")
		for {
			select {
			case data := <-processedDataChan:
				if data == nil {
					continue
				}
				memCache.Set(data)
				if cfg.LogProcessedEvents {
					log.Printf("LIVE: %s %s: T0 %s (%.6f) / T1 %s (%.6f) @ %s", data.Protocol, data.PoolAddress, data.Token0Symbol, data.PriceToken1ForToken0, data.Token1Symbol, data.PriceToken0ForToken1, data.Timestamp.Format(time.RFC3339))
				}
				select {
				case dbWriteChan <- data:
				case <-time.After(2 * time.Second):
					log.Printf("WARN: dbWriteChan full for pool %s. Discarding.", data.PoolAddress)
				case <-ctx.Done():
					log.Println("Cache Updater: Shutdown, not forwarding.")
				}
			case <-ctx.Done():
				log.Println("Cache Updater/DB Forwarder goroutine finished.")
				return
			}
		}
	}()

	// Goroutine: New Pool Manager (updated to use MulticallService for verification)
	wg.Add(1)
	go func() {
		defer wg.Done()
		log.Println("New Pool Manager goroutine started.")
		// verificationCtx is main ctx, verifyPool handles its own timeouts via mcService
		for {
			select {
			case newPool := <-newPoolChan:
				if newPool == nil {
					continue
				}

				// Verify with MulticallService
				verifyTimeoutCtx, verifyCancelSingle := context.WithTimeout(ctx, mcService.DefaultTimeout()) // Use service's default or a specific one
				isValid := verifyPool(verifyTimeoutCtx, mcService, newPool.Address, newPool.Protocol)
				verifyCancelSingle()

				if !isValid {
					log.Printf("POOL MGR: Discovered address %s (%s) failed verification. Ignoring.", newPool.Address.Hex(), newPool.Protocol)
					continue
				}

				poolAddrHexLower := strings.ToLower(newPool.Address.Hex())
				added := false
				var signalChan chan struct{}
				poolsMutex.Lock()
				if newPool.Protocol == uniswap.V2 { /* ... add to activeV2Pools, signal restartV2ListenerChan ... */
					if _, exists := activeV2Pools[poolAddrHexLower]; !exists {
						activeV2Pools[poolAddrHexLower] = newPool.Address
						log.Printf("POOL MGR: VERIFIED & Added new V2 Pool: %s. Total V2: %d", newPool.Address.Hex(), len(activeV2Pools))
						added = true
						signalChan = restartV2ListenerChan
					}
				} else if newPool.Protocol == uniswap.V3 { /* ... add to activeV3Pools, signal restartV3ListenerChan ... */
					if _, exists := activeV3Pools[poolAddrHexLower]; !exists {
						activeV3Pools[poolAddrHexLower] = newPool.Address
						log.Printf("POOL MGR: VERIFIED & Added new V3 Pool: %s. Total V3: %d", newPool.Address.Hex(), len(activeV3Pools))
						added = true
						signalChan = restartV3ListenerChan
					}
				}
				poolsMutex.Unlock()
				if added && signalChan != nil {
					select {
					case signalChan <- struct{}{}:
						log.Printf("POOL MGR: Signaled %s listener.", newPool.Protocol)
					default:
						log.Printf("POOL MGR: %s signal chan full.", newPool.Protocol)
					}
				}

			case <-ctx.Done():
				log.Println("New Pool Manager goroutine finished.")
				return
			}
		}
	}()

	// Pool Event Listener Managers (updated to pass MulticallService)
	wg.Add(1)
	go managePoolListener(ctx, &wg, ethClient, mcService, uniswap.V2, cfg.StartBlock, restartV2ListenerChan, processedDataChan, &activeV2Pools)
	wg.Add(1)
	go managePoolListener(ctx, &wg, ethClient, mcService, uniswap.V3, cfg.StartBlock, restartV3ListenerChan, processedDataChan, &activeV3Pools)

	// Factory Listeners (no change in invocation, they don't use mcService directly)
	if cfg.DiscoverV2Pools { /* ... */
		wg.Add(1)
		go func() {
			defer wg.Done()
			var cfa common.Address
			if common.IsHexAddress(cfg.UniswapV2Factory) {
				cfa = common.HexToAddress(cfg.UniswapV2Factory)
			}
			blockchain.ListenV2FactoryEvents(ctx, ethClient, cfa, newPoolChan, cfg.V2FactorySyncStartBlock)
		}()
	}
	if cfg.DiscoverV3Pools { /* ... */
		wg.Add(1)
		go func() {
			defer wg.Done()
			var cfa common.Address
			if common.IsHexAddress(cfg.UniswapV3Factory) {
				cfa = common.HexToAddress(cfg.UniswapV3Factory)
			}
			blockchain.ListenV3FactoryEvents(ctx, ethClient, cfa, newPoolChan, cfg.V3FactorySyncStartBlock)
		}()
	}

	log.Println("Application started with Multicall support. Press CTRL+C to exit.")
	if len(cfg.TrackedV2Pairs) > 0 {
		select {
		case restartV2ListenerChan <- struct{}{}:
		default:
		}
	}
	if len(cfg.TrackedV3Pools) > 0 {
		select {
		case restartV3ListenerChan <- struct{}{}:
		default:
		}
	}

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("Shutdown signal received...")
	cancel()
	shutdownComplete := make(chan struct{})
	go func() { wg.Wait(); close(shutdownComplete) }()
	select {
	case <-shutdownComplete:
		log.Println("All goroutines finished.")
	case <-time.After(45 * time.Second):
		log.Println("WARN: Timeout waiting for goroutines.")
	}
	log.Println("Application shut down.")
}

// managePoolListener updated to accept and pass MulticallService
func managePoolListener(
	mainCtx context.Context,
	mainWg *sync.WaitGroup,
	client *ethclient.Client, // ethclient for subscriptions
	mcService *blockchain.MulticallService, // mcService for initial data
	protocol uniswap.ProtocolVersion,
	defaultStartBlock uint64,
	restartChan <-chan struct{},
	outputChan chan<- *uniswap.PoolData,
	activePoolsMap *map[string]common.Address,
) {
	defer mainWg.Done()
	var listenerCtx context.Context
	var listenerCancel context.CancelFunc
	var listenerWg sync.WaitGroup
	log.Printf("%s Pool Event Listener Manager started.", protocol)

	for {
		select {
		case <-restartChan:
			log.Printf("%s Pool Mgr: Sig to (re)start listener.", protocol)
			if listenerCancel != nil {
				log.Printf("%s Pool Mgr: Cancelling prev listener...", protocol)
				listenerCancel()
				listenerWg.Wait()
				log.Printf("%s Pool Mgr: Prev listener stopped.", protocol)
			}

			poolsMutex.RLock()
			currentPoolsList := make([]common.Address, 0, len(*activePoolsMap))
			for _, addr := range *activePoolsMap {
				currentPoolsList = append(currentPoolsList, addr)
			}
			poolsMutex.RUnlock()

			if len(currentPoolsList) > 0 {
				listenerCtx, listenerCancel = context.WithCancel(mainCtx)
				listenerWg.Add(1)
				go func(p uniswap.ProtocolVersion, lCtx context.Context, poolsToListen []common.Address) {
					defer listenerWg.Done()
					if p == uniswap.V2 {
						blockchain.ListenV2Events(lCtx, client, mcService, poolsToListen, outputChan, defaultStartBlock)
					}
					if p == uniswap.V3 {
						blockchain.ListenV3Events(lCtx, client, mcService, poolsToListen, outputChan, defaultStartBlock)
					}
				}(protocol, listenerCtx, currentPoolsList)
			} else {
				log.Printf("%s Pool Mgr: No pools to listen for.", protocol)
			}

		case <-mainCtx.Done():
			if listenerCancel != nil {
				log.Printf("%s Pool Mgr: Main ctx done, cancelling listener...", protocol)
				listenerCancel()
				listenerWg.Wait()
				log.Printf("%s Pool Mgr: Listener stopped (main ctx).", protocol)
			}
			log.Printf("%s Pool Event Listener Manager finished.", protocol)
			return
		}
	}
}

// Add DefaultTimeout to MulticallService for use in main.go
// In blockchain/multicall_service.go, add:
// func (s *MulticallService) DefaultTimeout() time.Duration { return s.defaultTimeout }
