package Market

import (
	"fraktal/mev-bot-v2/Cache"
	"fraktal/mev-bot-v2/Database"
	"fraktal/mev-bot-v2/Debug"
	"fraktal/mev-bot-v2/Parser"
	"fraktal/mev-bot-v2/Pricing"
	"fraktal/mev-bot-v2/Scanner"
	"log"
	"sync"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
)

// Service handles the processing of market events (swaps) for known pools.
type Service struct {
	Cache        *Cache.Service
	Scanner      *Scanner.Service
	Parser       *Parser.Service
	DebugLogger  *Debug.Logger
	DBWriteQueue chan<- *Database.DBWriteRequest // CORRECTED: Use the DB writer channel
	pendingLogs  map[common.Address][]types.Log
	pendingLock  sync.Mutex
}

// NewService creates a new Market service.
func NewService(
	cache *Cache.Service,
	scanner *Scanner.Service,
	parser *Parser.Service,
	dbWriteQueue chan<- *Database.DBWriteRequest, // CORRECTED: Accept the channel
	debugLogger *Debug.Logger,
) *Service {
	return &Service{
		Cache:        cache,
		Scanner:      scanner,
		Parser:       parser,
		DBWriteQueue: dbWriteQueue,
		DebugLogger:  debugLogger,
		pendingLogs:  make(map[common.Address][]types.Log),
	}
}

// ProcessSwap takes a log for a known pool, updates its state, and triggers an arbitrage scan.
func (s *Service) ProcessSwap(vLog types.Log) {
	s.Cache.Lock.RLock()
	ticker, ok := s.Cache.PoolToTicker[vLog.Address]
	if !ok {
		s.Cache.Lock.RUnlock()
		return
	}

	var poolState *Cache.PoolState
	for _, ps := range s.Cache.TickerToPools[ticker] {
		if ps.Address == vLog.Address {
			poolState = ps
			break
		}
	}
	s.Cache.Lock.RUnlock()

	if poolState == nil {
		return
	}

	if poolState.IsV3Style {
		s.DebugLogger.LogJson("Raw V3 Log Received", vLog)
		swap, err := s.Parser.ParseV3Swap(vLog)
		if err != nil {
			log.Printf("Error parsing V3 swap for pool %s: %v", vLog.Address.Hex(), err)
			return
		}
		s.DebugLogger.LogJson("Parsed V3 Swap", swap)

		// CORRECTED: Send write request to the channel
		s.DBWriteQueue <- &Database.DBWriteRequest{
			Type: Database.SaveV3SwapRequest,
			V3Swap: &Database.V3SwapRecord{
				TxHash:      vLog.TxHash,
				LogIndex:    vLog.Index,
				PoolAddress: vLog.Address,
				Swap:        swap,
			},
		}

		s.Cache.Lock.Lock()
		s.DebugLogger.LogJson("V3 PoolState Before Update", poolState)
		poolState.SqrtPriceX96.Set(swap.SqrtPriceX96)
		poolState.Liquidity.Set(swap.Liquidity)
		poolState.Tick.Set(swap.Tick)
		s.DebugLogger.LogJson("V3 PoolState After Update", poolState)
		s.Cache.Lock.Unlock()
	} else {
		swap, err := s.Parser.ParseV2Swap(vLog)
		if err != nil {
			log.Printf("Error parsing V2 swap for pool %s: %v", vLog.Address.Hex(), err)
			return
		}

		// CORRECTED: Send write request to the channel
		s.DBWriteQueue <- &Database.DBWriteRequest{
			Type: Database.SaveV2SwapRequest,
			V2Swap: &Database.V2SwapRecord{
				TxHash:      vLog.TxHash,
				LogIndex:    vLog.Index,
				PoolAddress: vLog.Address,
				Swap:        swap,
			},
		}

		s.Cache.Lock.Lock()
		poolState.Reserve0.Add(poolState.Reserve0, swap.Amount0In).Sub(poolState.Reserve0, swap.Amount0Out)
		poolState.Reserve1.Add(poolState.Reserve1, swap.Amount1In).Sub(poolState.Reserve1, swap.Amount1Out)
		s.Cache.Lock.Unlock()
	}

	newPrice := Pricing.CalculatePriceFromState(poolState)
	if newPrice != nil && newPrice.Sign() > 0 {
		s.Cache.Lock.Lock()
		poolState.PoolPrice.Set(newPrice)
		addrTicker := s.Cache.PoolToTicker[vLog.Address]
		symTicker := poolState.SymbolTicker
		s.Cache.Lock.Unlock()

		s.Scanner.Scan(addrTicker, symTicker)
	}
}

// AddPendingLog adds a log to the queue for a pool that is pending discovery.
func (s *Service) AddPendingLog(vLog types.Log) {
	s.pendingLock.Lock()
	s.pendingLogs[vLog.Address] = append(s.pendingLogs[vLog.Address], vLog)
	s.pendingLock.Unlock()
}

// IsPending checks if a pool address has logs pending for discovery.
func (s *Service) IsPending(addr common.Address) bool {
	s.pendingLock.Lock()
	defer s.pendingLock.Unlock()
	_, pending := s.pendingLogs[addr]
	return pending
}

// ProcessPendingLogs processes all queued logs for a newly discovered pool.
func (s *Service) ProcessPendingLogs(poolAddress common.Address) {
	s.pendingLock.Lock()
	logsToProcess, exists := s.pendingLogs[poolAddress]
	if !exists {
		s.pendingLock.Unlock()
		return
	}
	delete(s.pendingLogs, poolAddress)
	s.pendingLock.Unlock()

	if len(logsToProcess) > 0 {
		log.Printf("Processing %d pending log(s) for newly discovered pool %s", len(logsToProcess), poolAddress.Hex())
		for _, vLog := range logsToProcess {
			s.ProcessSwap(vLog)
		}
	}
}

// CleanupPendingLogs removes the pending log queue for a given address.
func (s *Service) CleanupPendingLogs(poolAddress common.Address) {
	s.pendingLock.Lock()
	delete(s.pendingLogs, poolAddress)
	s.pendingLock.Unlock()
}
