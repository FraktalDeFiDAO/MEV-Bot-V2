package cache

import (
	"strings"
	"sync"

	"fraktal/mev-bot-v2/uniswap"
)

type MemoryCache struct {
	mu         sync.RWMutex
	latestData map[string]*uniswap.PoolData // poolAddress (lowercase) -> PoolData
}

func NewMemoryCache() *MemoryCache {
	return &MemoryCache{
		latestData: make(map[string]*uniswap.PoolData),
	}
}

func (mc *MemoryCache) Set(data *uniswap.PoolData) {
	if data == nil || data.PoolAddress == "" {
		return // Do not cache nil or invalid data
	}
	mc.mu.Lock()
	defer mc.mu.Unlock()
	mc.latestData[strings.ToLower(data.PoolAddress)] = data
}

func (mc *MemoryCache) Get(poolAddress string) (*uniswap.PoolData, bool) {
	mc.mu.RLock()
	defer mc.mu.RUnlock()
	data, found := mc.latestData[strings.ToLower(poolAddress)]
	// Return a copy to prevent modification of cached data by caller if PoolData fields were mutable (e.g. slices/maps not just big.Ints)
	// For this struct, direct return is okay as big.Ints are immutable reference types.
	return data, found
}

func (mc *MemoryCache) GetAll() []*uniswap.PoolData {
	mc.mu.RLock()
	defer mc.mu.RUnlock()
	allData := make([]*uniswap.PoolData, 0, len(mc.latestData))
	for _, data := range mc.latestData {
		allData = append(allData, data)
	}
	return allData
}

// Remove a pool from cache, e.g., if it's no longer tracked.
func (mc *MemoryCache) Remove(poolAddress string) {
	mc.mu.Lock()
	defer mc.mu.Unlock()
	delete(mc.latestData, strings.ToLower(poolAddress))
}
