// FILE: internal/defi/mockroute/mock_route.go
package mockroute

import (
	"errors"
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

type MockRoute struct {
	Name        string
	Profit      *big.Int
	GasEstimate *big.Int
	ProfitAsset string
	InterAsset  string
	ExecuteFail bool
}

func New(name string, profit *big.Int, gas *big.Int, asset string, inter string, fail bool) *MockRoute {
	return &MockRoute{
		Name:        name,
		Profit:      profit,
		GasEstimate: gas,
		ProfitAsset: asset,
		InterAsset:  inter,
		ExecuteFail: fail,
	}
}

func (m *MockRoute) EstimateProfit(client *ethclient.Client) (*big.Int, error) {
	return m.Profit, nil
}

func (m *MockRoute) SimulateMulticall(client *ethclient.Client) (*big.Int, error) {
	return m.Profit, nil
}

func (m *MockRoute) EstimateGasCost(client *ethclient.Client, from common.Address) (*big.Int, error) {
	return m.GasEstimate, nil
}

func (m *MockRoute) ExecuteWithFlashloan(client *ethclient.Client, txOpts *bind.TransactOpts) (*types.Transaction, error) {
	if m.ExecuteFail {
		return nil, errors.New("mock execution failed")
	}
	return &types.Transaction{}, nil
}

func (m *MockRoute) String() string {
	return m.Name
}

func (m *MockRoute) Tokens() (string, string) {
	return m.ProfitAsset, m.InterAsset
}
