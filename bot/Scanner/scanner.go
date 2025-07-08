package Scanner

import (
	"fraktal/mev-bot-v2/Cache"
	"fraktal/mev-bot-v2/Database"
	"fraktal/mev-bot-v2/Dispatcher"
	"log"
	"math/big"
	"strings"
)

// Service scans for arbitrage opportunities between pools of the same token pair.
type Service struct {
	Cache         *Cache.Service
	DispatcherHub *Dispatcher.Hub
	DBWriteQueue  chan<- *Database.DBWriteRequest
}

// NewService creates a new Scanner service.
func NewService(cache *Cache.Service, hub *Dispatcher.Hub, dbWriteQueue chan<- *Database.DBWriteRequest) *Service {
	return &Service{
		Cache:         cache,
		DispatcherHub: hub,
		DBWriteQueue:  dbWriteQueue,
	}
}

// Scan checks a given token pair for arbitrage opportunities.
func (s *Service) Scan(addrTicker, symTicker string) {
	s.Cache.Lock.RLock()
	defer s.Cache.Lock.RUnlock()
	pools := s.Cache.TickerToPools[addrTicker]
	if len(pools) < 2 {
		return
	}

	// Liquidity thresholds to filter out insignificant pools.
	liquidityThresholdV2 := new(big.Int).SetInt64(1000 * 1e6) // Example: $1000 in a stablecoin pool.
	liquidityThresholdV3 := new(big.Int).SetInt64(1e18)       // Example: 1 WETH.

	// Iterate through all pairs of pools for the given token ticker.
	for i := 0; i < len(pools); i++ {
		for j := i + 1; j < len(pools); j++ {
			poolA, poolB := pools[i], pools[j]

			// Check if both pools meet their respective liquidity thresholds.
			isLiquidA := isPoolLiquid(poolA, liquidityThresholdV2, liquidityThresholdV3)
			isLiquidB := isPoolLiquid(poolB, liquidityThresholdV2, liquidityThresholdV3)

			if !isLiquidA || !isLiquidB || poolA.Fee == nil || poolB.Fee == nil {
				continue
			}

			// Prices in the cache are already canonical (Price of T0 in terms of T1).
			priceA := poolA.PoolPrice
			priceB := poolB.PoolPrice

			if priceA.Cmp(big.NewFloat(0)) == 0 || priceB.Cmp(big.NewFloat(0)) == 0 {
				continue
			}

			// Determine which pool has the higher price and which has the lower price.
			var highPrice, lowPrice *big.Float
			var highPricePool, lowPricePool *Cache.PoolState
			if priceA.Cmp(priceB) > 0 {
				highPrice, lowPrice = priceA, priceB
				highPricePool, lowPricePool = poolA, poolB
			} else {
				highPrice, lowPrice = priceB, priceA
				highPricePool, lowPricePool = poolB, poolA
			}

			// Calculate the potential profit margin.
			spread := new(big.Float).Quo(highPrice, lowPrice)
			spread.Sub(spread, big.NewFloat(1))
			totalFees := new(big.Float).Add(lowPricePool.Fee, highPricePool.Fee)
			profitMargin := new(big.Float).Sub(spread, totalFees)
			profitThreshold := big.NewFloat(0.001) // 0.1% profit threshold before considering gas.

			if profitMargin.Cmp(profitThreshold) > 0 {
				profitMarginPct := new(big.Float).Mul(profitMargin, big.NewFloat(100))
				profitMarginF, _ := profitMarginPct.Float64()
				lowPriceF, _ := lowPrice.Float64()
				highPriceF, _ := highPrice.Float64()
				feeLowF, _ := lowPricePool.Fee.Float64()
				feeHighF, _ := highPricePool.Fee.Float64()

				log.Printf(`
--------------------------------------------------
!! PROFITABLE ARB OPPORTUNITY (Before Gas) !!
  Ticker: %s | Profit Margin: %.4f%%
  Buy at:  %s (%s) @ Price: %.6f (Fee: %.4f%%)
  Sell at: %s (%s) @ Price: %.6f (Fee: %.4f%%)
--------------------------------------------------`,
					symTicker, profitMarginF,
					lowPricePool.Address.Hex(), string(lowPricePool.Protocol), lowPriceF, feeLowF*100,
					highPricePool.Address.Hex(), string(highPricePool.Protocol), highPriceF, feeHighF*100,
				)

				// Create the enriched Opportunity struct.
				op := &Database.Opportunity{
					SymbolTicker:  symTicker,
					PercentDiff:   profitMarginF,
					Token0Address: strings.Split(addrTicker, "_")[0],
					Token1Address: strings.Split(addrTicker, "_")[1],
					Token0Symbol:  lowPricePool.Token0Symbol,
					Token1Symbol:  lowPricePool.Token1Symbol,
					PoolA: Database.PoolData{
						Address:  lowPricePool.Address.Hex(),
						Protocol: string(lowPricePool.Protocol),
						Factory:  lowPricePool.Factory.Hex(),
						Price:    lowPriceF,
						Fee:      feeLowF * 1000000,
					},
					PoolB: Database.PoolData{
						Address:  highPricePool.Address.Hex(),
						Protocol: string(highPricePool.Protocol),
						Factory:  highPricePool.Factory.Hex(),
						Price:    highPriceF,
						Fee:      feeHighF * 1000000,
					},
				}

				// Broadcast and save the opportunity.
				s.DispatcherHub.BroadcastOpportunity(op)

				// CORRECTED: Send a write request to the DB writer channel.
				s.DBWriteQueue <- &Database.DBWriteRequest{
					Type:        Database.SaveOpportunityRequest,
					Opportunity: op,
				}
			}
		}
	}
}

// isPoolLiquid checks if a pool meets liquidity thresholds.
func isPoolLiquid(pool *Cache.PoolState, v2Threshold, v3Threshold *big.Int) bool {
	if pool.IsV3Style {
		return pool.Liquidity != nil && pool.Liquidity.Cmp(v3Threshold) > 0
	}
	// For V2, check if both reserves are above the threshold.
	return pool.Reserve0 != nil && pool.Reserve1 != nil &&
		pool.Reserve0.Cmp(v2Threshold) > 0 && pool.Reserve1.Cmp(v2Threshold) > 0
}
