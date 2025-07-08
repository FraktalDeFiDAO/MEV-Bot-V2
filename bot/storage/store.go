package storage

import (
	"fraktal/mev-bot-v2/uniswap"
	// "time" // Not used in interface, but implementations might use it.
)

type DataStore interface {
	Connect() error
	Close() error
	Migrate() error // Setup DB schema
	SavePoolUpdate(data *uniswap.PoolData) error
	GetLatestPoolUpdate(poolAddress string) (*uniswap.PoolData, error)
	// Add more methods as needed, e.g., GetPoolsForPair(tokenA, tokenB string)
	// IsPoolTracked(poolAddress string, protocol uniswap.ProtocolVersion) (bool, error) // Could be useful
}
