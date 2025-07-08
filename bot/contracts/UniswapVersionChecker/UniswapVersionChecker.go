// Code generated - DO NOT EDIT.
// This file is a generated binding and any manual changes will be lost.

package UniswapVersionChecker

import (
	"errors"
	"math/big"
	"strings"

	ethereum "github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/event"
)

// Reference imports to suppress errors if they are not otherwise used.
var (
	_ = errors.New
	_ = big.NewInt
	_ = strings.NewReader
	_ = ethereum.NotFound
	_ = bind.Bind
	_ = common.Big1
	_ = types.BloomLookup
	_ = event.NewSubscription
	_ = abi.ConvertType
)

// UniswapVersionCheckerMetaData contains all meta data concerning the UniswapVersionChecker contract.
var UniswapVersionCheckerMetaData = &bind.MetaData{
	ABI: "[{\"type\":\"function\",\"name\":\"checkVersion\",\"inputs\":[{\"name\":\"_contractAddress\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"\",\"type\":\"uint8\",\"internalType\":\"enumUniswapVersionChecker.UniswapVersion\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"isUniswapV2\",\"inputs\":[{\"name\":\"_contractAddress\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"\",\"type\":\"bool\",\"internalType\":\"bool\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"isUniswapV3\",\"inputs\":[{\"name\":\"_contractAddress\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"\",\"type\":\"bool\",\"internalType\":\"bool\"}],\"stateMutability\":\"view\"}]",
}

// UniswapVersionCheckerABI is the input ABI used to generate the binding from.
// Deprecated: Use UniswapVersionCheckerMetaData.ABI instead.
var UniswapVersionCheckerABI = UniswapVersionCheckerMetaData.ABI

// UniswapVersionChecker is an auto generated Go binding around an Ethereum contract.
type UniswapVersionChecker struct {
	UniswapVersionCheckerCaller     // Read-only binding to the contract
	UniswapVersionCheckerTransactor // Write-only binding to the contract
	UniswapVersionCheckerFilterer   // Log filterer for contract events
}

// UniswapVersionCheckerCaller is an auto generated read-only Go binding around an Ethereum contract.
type UniswapVersionCheckerCaller struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// UniswapVersionCheckerTransactor is an auto generated write-only Go binding around an Ethereum contract.
type UniswapVersionCheckerTransactor struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// UniswapVersionCheckerFilterer is an auto generated log filtering Go binding around an Ethereum contract events.
type UniswapVersionCheckerFilterer struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// UniswapVersionCheckerSession is an auto generated Go binding around an Ethereum contract,
// with pre-set call and transact options.
type UniswapVersionCheckerSession struct {
	Contract     *UniswapVersionChecker // Generic contract binding to set the session for
	CallOpts     bind.CallOpts          // Call options to use throughout this session
	TransactOpts bind.TransactOpts      // Transaction auth options to use throughout this session
}

// UniswapVersionCheckerCallerSession is an auto generated read-only Go binding around an Ethereum contract,
// with pre-set call options.
type UniswapVersionCheckerCallerSession struct {
	Contract *UniswapVersionCheckerCaller // Generic contract caller binding to set the session for
	CallOpts bind.CallOpts                // Call options to use throughout this session
}

// UniswapVersionCheckerTransactorSession is an auto generated write-only Go binding around an Ethereum contract,
// with pre-set transact options.
type UniswapVersionCheckerTransactorSession struct {
	Contract     *UniswapVersionCheckerTransactor // Generic contract transactor binding to set the session for
	TransactOpts bind.TransactOpts                // Transaction auth options to use throughout this session
}

// UniswapVersionCheckerRaw is an auto generated low-level Go binding around an Ethereum contract.
type UniswapVersionCheckerRaw struct {
	Contract *UniswapVersionChecker // Generic contract binding to access the raw methods on
}

// UniswapVersionCheckerCallerRaw is an auto generated low-level read-only Go binding around an Ethereum contract.
type UniswapVersionCheckerCallerRaw struct {
	Contract *UniswapVersionCheckerCaller // Generic read-only contract binding to access the raw methods on
}

// UniswapVersionCheckerTransactorRaw is an auto generated low-level write-only Go binding around an Ethereum contract.
type UniswapVersionCheckerTransactorRaw struct {
	Contract *UniswapVersionCheckerTransactor // Generic write-only contract binding to access the raw methods on
}

// NewUniswapVersionChecker creates a new instance of UniswapVersionChecker, bound to a specific deployed contract.
func NewUniswapVersionChecker(address common.Address, backend bind.ContractBackend) (*UniswapVersionChecker, error) {
	contract, err := bindUniswapVersionChecker(address, backend, backend, backend)
	if err != nil {
		return nil, err
	}
	return &UniswapVersionChecker{UniswapVersionCheckerCaller: UniswapVersionCheckerCaller{contract: contract}, UniswapVersionCheckerTransactor: UniswapVersionCheckerTransactor{contract: contract}, UniswapVersionCheckerFilterer: UniswapVersionCheckerFilterer{contract: contract}}, nil
}

// NewUniswapVersionCheckerCaller creates a new read-only instance of UniswapVersionChecker, bound to a specific deployed contract.
func NewUniswapVersionCheckerCaller(address common.Address, caller bind.ContractCaller) (*UniswapVersionCheckerCaller, error) {
	contract, err := bindUniswapVersionChecker(address, caller, nil, nil)
	if err != nil {
		return nil, err
	}
	return &UniswapVersionCheckerCaller{contract: contract}, nil
}

// NewUniswapVersionCheckerTransactor creates a new write-only instance of UniswapVersionChecker, bound to a specific deployed contract.
func NewUniswapVersionCheckerTransactor(address common.Address, transactor bind.ContractTransactor) (*UniswapVersionCheckerTransactor, error) {
	contract, err := bindUniswapVersionChecker(address, nil, transactor, nil)
	if err != nil {
		return nil, err
	}
	return &UniswapVersionCheckerTransactor{contract: contract}, nil
}

// NewUniswapVersionCheckerFilterer creates a new log filterer instance of UniswapVersionChecker, bound to a specific deployed contract.
func NewUniswapVersionCheckerFilterer(address common.Address, filterer bind.ContractFilterer) (*UniswapVersionCheckerFilterer, error) {
	contract, err := bindUniswapVersionChecker(address, nil, nil, filterer)
	if err != nil {
		return nil, err
	}
	return &UniswapVersionCheckerFilterer{contract: contract}, nil
}

// bindUniswapVersionChecker binds a generic wrapper to an already deployed contract.
func bindUniswapVersionChecker(address common.Address, caller bind.ContractCaller, transactor bind.ContractTransactor, filterer bind.ContractFilterer) (*bind.BoundContract, error) {
	parsed, err := UniswapVersionCheckerMetaData.GetAbi()
	if err != nil {
		return nil, err
	}
	return bind.NewBoundContract(address, *parsed, caller, transactor, filterer), nil
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_UniswapVersionChecker *UniswapVersionCheckerRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _UniswapVersionChecker.Contract.UniswapVersionCheckerCaller.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_UniswapVersionChecker *UniswapVersionCheckerRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _UniswapVersionChecker.Contract.UniswapVersionCheckerTransactor.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_UniswapVersionChecker *UniswapVersionCheckerRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _UniswapVersionChecker.Contract.UniswapVersionCheckerTransactor.contract.Transact(opts, method, params...)
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_UniswapVersionChecker *UniswapVersionCheckerCallerRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _UniswapVersionChecker.Contract.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_UniswapVersionChecker *UniswapVersionCheckerTransactorRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _UniswapVersionChecker.Contract.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_UniswapVersionChecker *UniswapVersionCheckerTransactorRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _UniswapVersionChecker.Contract.contract.Transact(opts, method, params...)
}

// CheckVersion is a free data retrieval call binding the contract method 0x890e0eb7.
//
// Solidity: function checkVersion(address _contractAddress) view returns(uint8)
func (_UniswapVersionChecker *UniswapVersionCheckerCaller) CheckVersion(opts *bind.CallOpts, _contractAddress common.Address) (uint8, error) {
	var out []interface{}
	err := _UniswapVersionChecker.contract.Call(opts, &out, "checkVersion", _contractAddress)

	if err != nil {
		return *new(uint8), err
	}

	out0 := *abi.ConvertType(out[0], new(uint8)).(*uint8)

	return out0, err

}

// CheckVersion is a free data retrieval call binding the contract method 0x890e0eb7.
//
// Solidity: function checkVersion(address _contractAddress) view returns(uint8)
func (_UniswapVersionChecker *UniswapVersionCheckerSession) CheckVersion(_contractAddress common.Address) (uint8, error) {
	return _UniswapVersionChecker.Contract.CheckVersion(&_UniswapVersionChecker.CallOpts, _contractAddress)
}

// CheckVersion is a free data retrieval call binding the contract method 0x890e0eb7.
//
// Solidity: function checkVersion(address _contractAddress) view returns(uint8)
func (_UniswapVersionChecker *UniswapVersionCheckerCallerSession) CheckVersion(_contractAddress common.Address) (uint8, error) {
	return _UniswapVersionChecker.Contract.CheckVersion(&_UniswapVersionChecker.CallOpts, _contractAddress)
}

// IsUniswapV2 is a free data retrieval call binding the contract method 0x6d6793d1.
//
// Solidity: function isUniswapV2(address _contractAddress) view returns(bool)
func (_UniswapVersionChecker *UniswapVersionCheckerCaller) IsUniswapV2(opts *bind.CallOpts, _contractAddress common.Address) (bool, error) {
	var out []interface{}
	err := _UniswapVersionChecker.contract.Call(opts, &out, "isUniswapV2", _contractAddress)

	if err != nil {
		return *new(bool), err
	}

	out0 := *abi.ConvertType(out[0], new(bool)).(*bool)

	return out0, err

}

// IsUniswapV2 is a free data retrieval call binding the contract method 0x6d6793d1.
//
// Solidity: function isUniswapV2(address _contractAddress) view returns(bool)
func (_UniswapVersionChecker *UniswapVersionCheckerSession) IsUniswapV2(_contractAddress common.Address) (bool, error) {
	return _UniswapVersionChecker.Contract.IsUniswapV2(&_UniswapVersionChecker.CallOpts, _contractAddress)
}

// IsUniswapV2 is a free data retrieval call binding the contract method 0x6d6793d1.
//
// Solidity: function isUniswapV2(address _contractAddress) view returns(bool)
func (_UniswapVersionChecker *UniswapVersionCheckerCallerSession) IsUniswapV2(_contractAddress common.Address) (bool, error) {
	return _UniswapVersionChecker.Contract.IsUniswapV2(&_UniswapVersionChecker.CallOpts, _contractAddress)
}

// IsUniswapV3 is a free data retrieval call binding the contract method 0xd8844213.
//
// Solidity: function isUniswapV3(address _contractAddress) view returns(bool)
func (_UniswapVersionChecker *UniswapVersionCheckerCaller) IsUniswapV3(opts *bind.CallOpts, _contractAddress common.Address) (bool, error) {
	var out []interface{}
	err := _UniswapVersionChecker.contract.Call(opts, &out, "isUniswapV3", _contractAddress)

	if err != nil {
		return *new(bool), err
	}

	out0 := *abi.ConvertType(out[0], new(bool)).(*bool)

	return out0, err

}

// IsUniswapV3 is a free data retrieval call binding the contract method 0xd8844213.
//
// Solidity: function isUniswapV3(address _contractAddress) view returns(bool)
func (_UniswapVersionChecker *UniswapVersionCheckerSession) IsUniswapV3(_contractAddress common.Address) (bool, error) {
	return _UniswapVersionChecker.Contract.IsUniswapV3(&_UniswapVersionChecker.CallOpts, _contractAddress)
}

// IsUniswapV3 is a free data retrieval call binding the contract method 0xd8844213.
//
// Solidity: function isUniswapV3(address _contractAddress) view returns(bool)
func (_UniswapVersionChecker *UniswapVersionCheckerCallerSession) IsUniswapV3(_contractAddress common.Address) (bool, error) {
	return _UniswapVersionChecker.Contract.IsUniswapV3(&_UniswapVersionChecker.CallOpts, _contractAddress)
}
