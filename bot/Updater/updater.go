package Updater

import (
	"context"
	"fraktal/mev-bot-v2/Cache"
	"fraktal/mev-bot-v2/Multicall"
	"fraktal/mev-bot-v2/Pricing"
	"log"
	"time"
)

// Service is responsible for periodically refreshing the state of all cached pools.
type Service struct {
	Cache            *Cache.Service
	MulticallService *Multicall.MulticallService
	Interval         time.Duration
}

// New creates a new Updater service with a configurable interval.
func New(cache *Cache.Service, mcService *Multicall.MulticallService, interval time.Duration) *Service {
	return &Service{
		Cache:            cache,
		MulticallService: mcService,
		Interval:         interval,
	}
}

// Run starts the periodic update loop.
func (s *Service) Run() {
	log.Printf("Updater Service running... (Interval: %v)", s.Interval)
	ticker := time.NewTicker(s.Interval)
	defer ticker.Stop()

	for range ticker.C {
		s.updatePools()
	}
}

// updatePools fetches the latest reserves and state for all known pools.
func (s *Service) updatePools() {
	s.Cache.Lock.RLock()
	if len(s.Cache.PoolToTicker) == 0 {
		s.Cache.Lock.RUnlock()
		return
	}

	// Create a snapshot of the pools to update to avoid holding the lock for too long.
	poolsToUpdate := make([]*Cache.PoolState, 0, len(s.Cache.PoolToTicker))
	for _, poolStates := range s.Cache.TickerToPools {
		poolsToUpdate = append(poolsToUpdate, poolStates...)
	}
	s.Cache.Lock.RUnlock()

	if len(poolsToUpdate) == 0 {
		return
	}

	log.Printf("Updater: Refreshing reserves for %d pools...", len(poolsToUpdate))
	reserves, err := s.MulticallService.FetchPoolReservesBatch(context.Background(), poolsToUpdate)
	if err != nil {
		log.Printf("Updater: Error fetching batch reserves: %v", err)
		return
	}

	// It's crucial to acquire a full write lock for the duration of the updates
	// to prevent race conditions with the main event processing loop.
	s.Cache.Lock.Lock()
	defer s.Cache.Lock.Unlock()

	for addr, res := range reserves {
		if state, ok := s.Cache.GetPoolByAddress(addr); ok {
			state.Reserve0.Set(res.Reserve0)
			state.Reserve1.Set(res.Reserve1)

			// If it's a V3-style pool, we also need to refresh its other state variables.
			if state.IsV3Style {
				_, _, sqrtPrice, tick, liquidity, _ := s.MulticallService.FetchV3PoolState(addr)
				if liquidity != nil {
					state.Liquidity.Set(liquidity)
					state.SqrtPriceX96.Set(sqrtPrice)
					state.Tick.Set(tick)
				}
			}
			// LOGIC FIX: After updating reserves/state, we must recalculate the price.
			state.PoolPrice.Set(Pricing.CalculatePriceFromState(state))
		}
	}
}
