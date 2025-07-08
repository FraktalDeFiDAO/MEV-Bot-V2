package uniswap

import (
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
)

var (
	ERC20ABI abi.ABI
)

func init() {
	const erc20AbiJson = `[
		{"constant":true,"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},
		{"constant":true,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},
		{"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"stateMutability":"view","type":"function"}
	]`
	var err error
	ERC20ABI, err = abi.JSON(strings.NewReader(erc20AbiJson))
	if err != nil {
		panic("Failed to parse ERC20 ABI: " + err.Error())
	}
}
