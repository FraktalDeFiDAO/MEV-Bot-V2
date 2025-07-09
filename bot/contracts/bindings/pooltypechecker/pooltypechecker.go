package pooltypechecker

import (
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
)

// PoolTypeChecker is a minimal stub for compilation.
type PoolTypeChecker struct{}

func NewPoolTypeChecker(address common.Address, backend bind.ContractBackend) (*PoolTypeChecker, error) {
	return &PoolTypeChecker{}, nil
}

func (p *PoolTypeChecker) CheckPoolType(opts *bind.CallOpts, poolAddress common.Address) (uint8, error) {
	return 0, nil
}
