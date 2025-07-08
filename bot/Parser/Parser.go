package Parser

import (
	"fmt"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
)

var (
	V2ABI abi.ABI
	V3ABI abi.ABI
)

// Service holds the ABIs for parsing.
type Service struct{}

// NewService creates a new Parser service.
func NewService() (*Service, error) {
	var err error
	v2AbiString := `[{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount0Out","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1Out","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Swap","type":"event"}]`
	v3AbiString := `[{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":true,"internalType":"address","name":"recipient","type":"address"},{"indexed":false,"internalType":"int256","name":"amount0","type":"int256"},{"indexed":false,"internalType":"int256","name":"amount1","type":"int256"},{"indexed":false,"internalType":"uint160","name":"sqrtPriceX96","type":"uint160"},{"indexed":false,"internalType":"uint128","name":"liquidity","type":"uint128"},{"indexed":false,"internalType":"int24","name":"tick","type":"int24"}],"name":"Swap","type":"event"}]`

	V2ABI, err = abi.JSON(strings.NewReader(v2AbiString))
	if err != nil {
		return nil, err
	}
	V3ABI, err = abi.JSON(strings.NewReader(v3AbiString))
	if err != nil {
		return nil, err
	}
	return &Service{}, nil
}

// LogSwapV2 holds parsed data for a Uniswap V2 swap.
type LogSwapV2 struct {
	Sender     common.Address
	Amount0In  *big.Int
	Amount1In  *big.Int
	Amount0Out *big.Int
	Amount1Out *big.Int
	To         common.Address
}

// LogSwapV3 holds parsed data for a Uniswap V3 swap.
type LogSwapV3 struct {
	Sender       common.Address
	Recipient    common.Address
	Amount0      *big.Int
	Amount1      *big.Int
	SqrtPriceX96 *big.Int
	Liquidity    *big.Int
	Tick         *big.Int
}

// ParseV2Swap decodes a raw V2 swap log.
func (s *Service) ParseV2Swap(vLog types.Log) (*LogSwapV2, error) {
	var swapEvent LogSwapV2
	err := V2ABI.UnpackIntoInterface(&swapEvent, "Swap", vLog.Data)
	if err != nil {
		return nil, fmt.Errorf("error unpacking V2 swap data: %w", err)
	}
	// Indexed fields are in Topics
	swapEvent.Sender = common.BytesToAddress(vLog.Topics[1].Bytes())
	swapEvent.To = common.BytesToAddress(vLog.Topics[2].Bytes())
	return &swapEvent, nil
}

// CORRECTED: This now correctly unpacks indexed and non-indexed fields.
func (s *Service) ParseV3Swap(vLog types.Log) (*LogSwapV3, error) {
	var swapEvent LogSwapV3

	// A temporary struct for ONLY the non-indexed fields in the 'data' payload.
	var nonIndexedData struct {
		Amount0      *big.Int
		Amount1      *big.Int
		SqrtPriceX96 *big.Int
		Liquidity    *big.Int
		Tick         *big.Int
	}

	// Step 1: Unpack ONLY the non-indexed fields from vLog.Data.
	// This is the crucial fix.
	err := V3ABI.UnpackIntoInterface(&nonIndexedData, "Swap", vLog.Data)
	if err != nil {
		return nil, fmt.Errorf("error unpacking V3 swap data: %w", err)
	}

	// Step 2: Assign the correctly unpacked data.
	swapEvent.Amount0 = nonIndexedData.Amount0
	swapEvent.Amount1 = nonIndexedData.Amount1
	swapEvent.SqrtPriceX96 = nonIndexedData.SqrtPriceX96
	swapEvent.Liquidity = nonIndexedData.Liquidity
	swapEvent.Tick = nonIndexedData.Tick

	// Step 3: Read the indexed fields from the Topics array.
	if len(vLog.Topics) > 2 {
		swapEvent.Sender = common.BytesToAddress(vLog.Topics[1].Bytes())
		swapEvent.Recipient = common.BytesToAddress(vLog.Topics[2].Bytes())
	} else {
		return nil, fmt.Errorf("V3 swap log is missing sender/recipient topics")
	}

	return &swapEvent, nil
}
