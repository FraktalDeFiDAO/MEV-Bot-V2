package Cache

import (
	"fraktal/mev-bot-v2/uniswap"
	"math/big"
	"sync"

	"github.com/ethereum/go-ethereum/common"
)

// PoolState holds the dynamic information for a single liquidity pool.
type PoolState struct {
	Address        common.Address
	Factory        common.Address
	Protocol       uniswap.ProtocolVersion
	IsV3Style      bool
	IsReversed     bool // Tracks if T0/T1 are swapped relative to the common symbol ticker.
	Fee            *big.Float
	PoolPrice      *big.Float
	SymbolTicker   string
	Token0         common.Address
	Token1         common.Address
	Token0Decimals uint8
	Token1Decimals uint8
	Token0Symbol   string
	Token1Symbol   string

	// V2 specific fields
	Reserve0 *big.Int
	Reserve1 *big.Int

	// V3-style specific fields
	Liquidity    *big.Int
	SqrtPriceX96 *big.Int
	Tick         *big.Int
}

// Service is the central, thread-safe cache for market data.
type Service struct {
	TickerToPools map[string][]*PoolState
	PoolToTicker  map[common.Address]string
	Lock          sync.RWMutex
}

// New creates a new, initialized Cache service.
func New() *Service {
	return &Service{
		TickerToPools: make(map[string][]*PoolState),
		PoolToTicker:  make(map[common.Address]string),
	}
}

// GetPoolByAddress is a helper method to retrieve a specific pool's state by its address.
// This requires a read lock to be safe for concurrent access.
func (s *Service) GetPoolByAddress(address common.Address) (*PoolState, bool) {
	s.Lock.RLock()
	defer s.Lock.RUnlock()

	ticker, ok := s.PoolToTicker[address]
	if !ok {
		return nil, false
	}

	pools, ok := s.TickerToPools[ticker]
	if !ok {
		return nil, false
	}

	for _, pool := range pools {
		if pool.Address == address {
			return pool, true
		}
	}

	return nil, false
}
