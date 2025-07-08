// bot/uniswap/common.go

package uniswap

import (
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
)

// ProtocolVersion is a string alias for DEX protocol names.
type ProtocolVersion string

// Constants for the protocol versions, matching your contract's logic.
const (
	V2                 ProtocolVersion = "UniswapV2"
	V3                 ProtocolVersion = "UniswapV3"
	AlgebraV1          ProtocolVersion = "ALGEBRA_V1"
	AlgebraV1_Adaptive ProtocolVersion = "ALGEBRA_V1_ADAPTIVE" // CORRECTED NAME
	AlgebraV1_DBF      ProtocolVersion = "ALGEBRA_V1_DBF"
	AlgebraV2_DBF      ProtocolVersion = "ALGEBRA_V2_DBF"
	Unknown            ProtocolVersion = "Unknown"
)

// PoolType mirrors the enum in the PoolTypeChecker.sol smart contract.
const (
	PoolTypeNONE              uint8 = 0
	PoolTypeUNISWAPV2         uint8 = 1
	PoolTypeUNISWAPV3         uint8 = 2
	PoolTypeALGEBRAV1         uint8 = 3
	PoolTypeALGEBRAV1ADAPTIVE uint8 = 4 // CORRECTED NAME
	PoolTypeALGEBRAV1DBF      uint8 = 5
	PoolTypeALGEBRAV2DBF      uint8 = 6
)

// ... (Rest of the file is unchanged) ...
type PoolData struct {
	PoolAddress          string          `json:"pool_address"`
	Protocol             ProtocolVersion `json:"protocol"`
	Token0Address        string          `json:"token0_address"`
	Token1Address        string          `json:"token1_address"`
	Token0Symbol         string          `json:"token0_symbol"`
	Token1Symbol         string          `json:"token1_symbol"`
	Token0Decimals       uint8           `json:"token0_decimals"`
	Token1Decimals       uint8           `json:"token1_decimals"`
	Timestamp            time.Time       `json:"timestamp"`
	Reserve0             *big.Int        `json:"reserve0,omitempty"`
	Reserve1             *big.Int        `json:"reserve1,omitempty"`
	SqrtPriceX96         *big.Int        `json:"sqrt_price_x96,omitempty"`
	Liquidity            *big.Int        `json:"liquidity,omitempty"`
	Tick                 *big.Int        `json:"tick,omitempty"`
	PriceToken0ForToken1 float64         `json:"price_token0_for_token1"`
	PriceToken1ForToken0 float64         `json:"price_token1_for_token0"`
	RawEvent             types.Log       `json:"-"`
}

type NewPoolNotification struct {
	Address     common.Address
	Protocol    ProtocolVersion
	Token0      common.Address
	Token1      common.Address
	Fee         *big.Int
	BlockNumber uint64
	TxHash      common.Hash
}
