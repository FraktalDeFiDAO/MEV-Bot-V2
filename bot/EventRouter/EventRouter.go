package EventRouter

import (
	"fraktal/mev-bot-v2/Cache"
	"fraktal/mev-bot-v2/Discovery"
	"fraktal/mev-bot-v2/Market"

	"github.com/ethereum/go-ethereum/core/types"
)

// Service routes incoming blockchain logs to the appropriate handler.
type Service struct {
	Cache            *Cache.Service
	MarketService    *Market.Service
	DiscoveryService *Discovery.Service
}

// NewService creates a new EventRouter service.
func NewService(cache *Cache.Service, market *Market.Service, discovery *Discovery.Service) *Service {
	return &Service{
		Cache:            cache,
		MarketService:    market,
		DiscoveryService: discovery,
	}
}

// HandleLog is the entry point for all incoming logs from the subscription.
func (s *Service) HandleLog(vLog types.Log) {
	s.Cache.Lock.RLock()
	_, isKnown := s.Cache.PoolToTicker[vLog.Address]
	s.Cache.Lock.RUnlock()

	if isKnown {
		// If the pool is already in our cache, it's a market event.
		s.MarketService.ProcessSwap(vLog)
	} else {
		// If we don't know the pool, it's a potential new discovery.
		// We check if it's already being processed to avoid redundant work.
		if !s.MarketService.IsPending(vLog.Address) {
			s.DiscoveryService.DiscoveryQueue <- vLog.Address
		}
		// Queue the log to be processed after discovery is complete.
		s.MarketService.AddPendingLog(vLog)
	}
}
