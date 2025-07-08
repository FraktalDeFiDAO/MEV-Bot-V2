package uniswap

import (
	"fmt"
	"math/big"
	"strings"

	uniswapv3pool "fraktal/mev-bot-v2/contracts/bindings/iuniswapv3pool" // IMPORT THE BINDING

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
)

// ... (structs are unchanged) ...
type V3SwapEvent struct {
	Sender       common.Address
	Recipient    common.Address
	Amount0      *big.Int
	Amount1      *big.Int
	SqrtPriceX96 *big.Int
	Liquidity    *big.Int
	Tick         *big.Int
}

type V3PoolCreatedEvent struct {
	Token0      common.Address
	Token1      common.Address
	Fee         *big.Int
	TickSpacing *big.Int
	Pool        common.Address
}

var (
	V3PoolABI        abi.ABI
	SwapEvent        common.Hash
	V3FactoryABI     abi.ABI
	PoolCreatedEvent common.Hash
)

func init() {
	var err error
	// Use the ABI from the generated binding
	V3PoolABI, err := uniswapv3pool.IUniswapV3PoolMetaData.GetAbi()
	if err != nil {
		panic("Failed to parse internal UniswapV3Pool ABI: " + err.Error())
	}
	SwapEvent = V3PoolABI.Events["Swap"].ID

	const factoryAbiJson = `[{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"token0","type":"address"},{"indexed":true,"internalType":"address","name":"token1","type":"address"},{"indexed":true,"internalType":"uint24","name":"fee","type":"uint24"},{"indexed":false,"internalType":"int24","name":"tickSpacing","type":"int24"},{"indexed":false,"internalType":"address","name":"pool","type":"address"}],"name":"PoolCreated","type":"event"}]`
	V3FactoryABI, err = abi.JSON(strings.NewReader(factoryAbiJson))
	if err != nil {
		panic("Failed to parse UniswapV3Factory ABI: " + err.Error())
	}
	PoolCreatedEvent = V3FactoryABI.Events["PoolCreated"].ID
}

// ... (The rest of the file remains the same) ...
func ParseV3Swap(log types.Log) (*V3SwapEvent, error) {
	var event V3SwapEvent
	err := V3PoolABI.UnpackIntoInterface(&event, "Swap", log.Data)
	if err != nil {
		return nil, fmt.Errorf("unpack V3 Swap log data: %w", err)
	}

	if len(log.Topics) > 2 {
		if event.Sender == (common.Address{}) {
			event.Sender = common.BytesToAddress(log.Topics[1].Bytes())
		}
		if event.Recipient == (common.Address{}) {
			event.Recipient = common.BytesToAddress(log.Topics[2].Bytes())
		}
	}
	return &event, nil
}

func ParseV3PoolCreated(log types.Log) (*V3PoolCreatedEvent, error) {
	var event V3PoolCreatedEvent

	var nonIndexedData struct {
		TickSpacing *big.Int
		Pool        common.Address
	}
	err := V3FactoryABI.UnpackIntoInterface(&nonIndexedData, "PoolCreated", log.Data)
	if err != nil {
		if len(log.Data) == 64 {
			event.TickSpacing = new(big.Int).SetBytes(log.Data[0:32])
			event.Pool = common.BytesToAddress(log.Data[32:64])
		} else {
			return nil, fmt.Errorf("error unpacking V3PoolCreated log data (len %d), direct error: %w", len(log.Data), err)
		}
	} else {
		event.TickSpacing = nonIndexedData.TickSpacing
		event.Pool = nonIndexedData.Pool
	}

	if len(log.Topics) < 4 {
		return nil, fmt.Errorf("not enough topics for V3PoolCreated event, got %d, expected at least 4", len(log.Topics))
	}
	event.Token0 = common.BytesToAddress(log.Topics[1].Bytes())
	event.Token1 = common.BytesToAddress(log.Topics[2].Bytes())
	event.Fee = new(big.Int).SetBytes(log.Topics[3].Bytes())
	return &event, nil
}
