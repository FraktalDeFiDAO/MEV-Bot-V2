package arb

import (
	"log"
	"strings"

	"fraktal/mev-bot-v2/Debug"
	"fraktal/mev-bot-v2/cache"
	"fraktal/mev-bot-v2/uniswap"
)

func canonicalPair(a, b string) string {
	a = strings.ToLower(a)
	b = strings.ToLower(b)
	if a < b {
		return a + "_" + b
	}
	return b + "_" + a
}

// Scan examines cached pools and logs arbitrage opportunities when the price
// spread between any two pools of the same token pair exceeds the given
// threshold (e.g. 0.001 for 0.1%). If a debug logger is provided, details are
// written there as JSON for easier inspection.
func Scan(mc *cache.MemoryCache, threshold float64, dbg *Debug.Logger) {
	pools := mc.GetAll()
	pairMap := make(map[string][]*uniswap.PoolData)
	for _, p := range pools {
		key := canonicalPair(p.Token0Address, p.Token1Address)
		pairMap[key] = append(pairMap[key], p)
	}

	for _, list := range pairMap {
		if len(list) < 2 {
			continue
		}
		for i := 0; i < len(list); i++ {
			for j := i + 1; j < len(list); j++ {
				pA, pB := list[i], list[j]
				priceA := pA.PriceToken0ForToken1
				priceB := pB.PriceToken0ForToken1
				var high, low *uniswap.PoolData
				if priceA > priceB {
					high, low = pA, pB
				} else {
					high, low = pB, pA
				}
				if low.PriceToken0ForToken1 == 0 {
					continue
				}
				spread := (high.PriceToken0ForToken1 - low.PriceToken0ForToken1) / low.PriceToken0ForToken1
				if spread > threshold {
					msg := map[string]interface{}{
						"pair":       canonicalPair(pA.Token0Address, pA.Token1Address),
						"low_pool":   low.PoolAddress,
						"high_pool":  high.PoolAddress,
						"low_price":  low.PriceToken0ForToken1,
						"high_price": high.PriceToken0ForToken1,
						"spread_pct": spread * 100,
					}
					if dbg != nil {
						dbg.LogJson("Arbitrage", msg)
					} else {
						log.Printf("ARB %s: buy at %.6f (%s), sell at %.6f (%s) => %.4f%%", msg["pair"], msg["low_price"], msg["low_pool"], msg["high_price"], msg["high_pool"], msg["spread_pct"])
					}
				}
			}
		}
	}
}
