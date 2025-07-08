package uniswap

import (
	"fmt"
	"math/big"
	"strings"

	uniswapv2pair "fraktal/mev-bot-v2/contracts/bindings/iuniswapv2pair"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types" // CORRECTED IMPORT PATH
)

type V2SyncEvent struct {
	Reserve0 *big.Int
	Reserve1 *big.Int
}

type V2PairCreatedEvent struct {
	Token0         common.Address
	Token1         common.Address
	Pair           common.Address
	AllPairsLength *big.Int
}

var (
	V2PairABI        abi.ABI
	SyncEvent        common.Hash
	V2FactoryABI     abi.ABI
	PairCreatedEvent common.Hash
)

func init() {
	var err error
	// Use the ABI from the generated binding
	V2PairABI, err := uniswapv2pair.IUniswapV2PairMetaData.GetAbi()
	if err != nil {
		panic("Failed to parse internal UniswapV2Pair ABI: " + err.Error())
	}
	SyncEvent = V2PairABI.Events["Sync"].ID

	const factoryAbiJson = `[{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"token0","type":"address"},{"indexed":true,"internalType":"address","name":"token1","type":"address"},{"indexed":false,"internalType":"address","name":"pair","type":"address"},{"indexed":false,"internalType":"uint256","name":"allPairsLength","type":"uint256"}],"name":"PairCreated","type":"event"}]`
	V2FactoryABI, err = abi.JSON(strings.NewReader(factoryAbiJson))
	if err != nil {
		panic("Failed to parse UniswapV2Factory ABI: " + err.Error())
	}
	PairCreatedEvent = V2FactoryABI.Events["PairCreated"].ID
}

func ParseV2Sync(log types.Log) (*V2SyncEvent, error) {
	var event V2SyncEvent
	err := V2PairABI.UnpackIntoInterface(&event, "Sync", log.Data)
	if err != nil {
		return nil, err
	}
	return &event, nil
}

func ParseV2PairCreated(log types.Log) (*V2PairCreatedEvent, error) {
	var event V2PairCreatedEvent
	var nonIndexedData struct {
		Pair           common.Address
		AllPairsLength *big.Int
	}
	err := V2FactoryABI.UnpackIntoInterface(&nonIndexedData, "PairCreated", log.Data)
	if err != nil {
		if len(log.Data) == 64 {
			event.Pair = common.BytesToAddress(log.Data[0:32])
			event.AllPairsLength = new(big.Int).SetBytes(log.Data[32:64])
		} else {
			return nil, fmt.Errorf("error unpacking V2PairCreated log data (len %d), direct error: %w", len(log.Data), err)
		}
	} else {
		event.Pair = nonIndexedData.Pair
		event.AllPairsLength = nonIndexedData.AllPairsLength
	}
	if len(log.Topics) < 3 {
		return nil, fmt.Errorf("not enough topics for V2PairCreated event, got %d, expected at least 3", len(log.Topics))
	}
	event.Token0 = common.BytesToAddress(log.Topics[1].Bytes())
	event.Token1 = common.BytesToAddress(log.Topics[2].Bytes())
	return &event, nil
}
