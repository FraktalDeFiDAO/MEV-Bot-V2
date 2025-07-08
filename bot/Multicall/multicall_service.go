package Multicall

import (
	"context"
	"fmt"
	"fraktal/mev-bot-v2/Cache"
	"log"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/forta-network/go-multicall"
	lru "github.com/hashicorp/golang-lru/v2"
)

var (
	erc20AbiString  = `[{"constant":true,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"}]`
	v2PairAbiString = `[{"constant":true,"inputs":[],"name":"token0","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[],"name":"token1","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[],"name":"factory","outputs":[{"name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[],"name":"getReserves","outputs":[{"name":"_reserve0","type":"uint112"},{"name":"_reserve1","type":"uint112"},{"name":"_blockTimestampLast","type":"uint32"}],"payable":false,"stateMutability":"view","type":"function"}]`
	v3PoolAbiString = `[{"constant":true,"inputs":[],"name":"token0","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[],"name":"token1","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[],"name":"factory","outputs":[{"name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[],"name":"fee","outputs":[{"name":"","type":"uint24"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[],"name":"slot0","outputs":[{"internalType":"uint160","name":"sqrtPriceX96","type":"uint160"},{"internalType":"int24","name":"tick","type":"int24"}],"payable":false,"stateMutability":"view","type":"function"}, {"constant":true,"inputs":[],"name":"liquidity","outputs":[{"internalType":"uint128","name":"","type":"uint128"}],"payable":false,"stateMutability":"view","type":"function"}]`
)

type TokenMetadata struct {
	Symbol   string
	Decimals uint8
}

type MulticallService struct {
	caller     *multicall.Caller
	tokenCache *lru.Cache[string, TokenMetadata]
}

func NewMulticallService(rpcURL string) (*MulticallService, error) {
	caller, err := multicall.Dial(context.Background(), rpcURL)
	if err != nil {
		return nil, fmt.Errorf("failed to dial for multicall: %w", err)
	}
	tokenCache, err := lru.New[string, TokenMetadata](10000)
	if err != nil {
		return nil, fmt.Errorf("failed to create token metadata cache: %w", err)
	}
	return &MulticallService{
		caller:     caller,
		tokenCache: tokenCache,
	}, nil
}

type tokenOutput struct{ Addr common.Address }
type feeOutput struct{ Fee *big.Int }
type reservesOutput struct {
	Reserve0 *big.Int
	Reserve1 *big.Int
}
type balanceOutput struct{ Balance *big.Int }

type v3Slot0Output struct {
	SqrtPriceX96 *big.Int `abi:"sqrtPriceX96"`
	Tick         *big.Int `abi:"tick"`
}
type v3LiquidityOutput struct{ Liquidity *big.Int }
type v2ReservesOutput struct {
	Reserve0           *big.Int `abi:"_reserve0"`
	Reserve1           *big.Int `abi:"_reserve1"`
	BlockTimestampLast uint32   `abi:"_blockTimestampLast"`
}

func (s *MulticallService) FetchPoolReservesBatch(ctx context.Context, pools []*Cache.PoolState) (map[common.Address]*reservesOutput, error) {
	var calls []*multicall.Call
	type callInfo struct {
		pool    *Cache.PoolState
		resOut  *v2ReservesOutput
		bal0Out *balanceOutput
		bal1Out *balanceOutput
	}
	var callInfos []callInfo

	for _, pool := range pools {
		if !pool.IsV3Style { // V2 style
			contract, _ := multicall.NewContract(v2PairAbiString, pool.Address.Hex())
			resOut := new(v2ReservesOutput)
			calls = append(calls, contract.NewCall(resOut, "getReserves").AllowFailure())
			callInfos = append(callInfos, callInfo{pool: pool, resOut: resOut})
		} else { // V3 Style
			token0contract, _ := multicall.NewContract(erc20AbiString, pool.Token0.Hex())
			token1contract, _ := multicall.NewContract(erc20AbiString, pool.Token1.Hex())
			bal0Out, bal1Out := new(balanceOutput), new(balanceOutput)
			calls = append(calls, token0contract.NewCall(bal0Out, "balanceOf", pool.Address).AllowFailure())
			calls = append(calls, token1contract.NewCall(bal1Out, "balanceOf", pool.Address).AllowFailure())
			callInfos = append(callInfos, callInfo{pool: pool, bal0Out: bal0Out, bal1Out: bal1Out})
		}
	}

	if len(calls) == 0 {
		return make(map[common.Address]*reservesOutput), nil
	}

	_, err := s.caller.Call(&bind.CallOpts{Context: ctx}, calls...)
	if err != nil {
		return nil, fmt.Errorf("multicall network error: %w", err)
	}

	successResults := make(map[common.Address]*reservesOutput)
	callIndex := 0
	for _, info := range callInfos {
		if !info.pool.IsV3Style { // V2
			call := calls[callIndex]
			callIndex++

			if call.Failed || info.resOut == nil || info.resOut.Reserve0 == nil || info.resOut.Reserve1 == nil {
				continue
			}
			successResults[info.pool.Address] = &reservesOutput{
				Reserve0: info.resOut.Reserve0,
				Reserve1: info.resOut.Reserve1,
			}
		} else { // V3
			call0, call1 := calls[callIndex], calls[callIndex+1]
			callIndex += 2
			if call0.Failed || call1.Failed || info.bal0Out.Balance == nil || info.bal1Out.Balance == nil {
				continue
			}
			successResults[info.pool.Address] = &reservesOutput{
				Reserve0: info.bal0Out.Balance,
				Reserve1: info.bal1Out.Balance,
			}
		}
	}
	return successResults, nil
}

func (s *MulticallService) FetchV2PairData(pairAddr common.Address) (common.Address, common.Address, common.Address, error) {
	pairContract, err := multicall.NewContract(v2PairAbiString, pairAddr.Hex())
	if err != nil {
		return common.Address{}, common.Address{}, common.Address{}, err
	}
	t0Out, t1Out, facOut := new(tokenOutput), new(tokenOutput), new(tokenOutput)
	calls := []*multicall.Call{
		pairContract.NewCall(t0Out, "token0"),
		pairContract.NewCall(t1Out, "token1"),
		pairContract.NewCall(facOut, "factory"),
	}
	_, err = s.caller.Call(nil, calls...)
	if err != nil {
		return common.Address{}, common.Address{}, common.Address{}, err
	}
	return t0Out.Addr, t1Out.Addr, facOut.Addr, nil
}

func (s *MulticallService) FetchV3StyleTokensAndFactory(poolAddr common.Address) (common.Address, common.Address, common.Address, error) {
	poolContract, err := multicall.NewContract(v3PoolAbiString, poolAddr.Hex())
	if err != nil {
		return common.Address{}, common.Address{}, common.Address{}, err
	}
	t0Out, t1Out, facOut := new(tokenOutput), new(tokenOutput), new(tokenOutput)
	calls := []*multicall.Call{
		poolContract.NewCall(t0Out, "token0"),
		poolContract.NewCall(t1Out, "token1"),
		poolContract.NewCall(facOut, "factory"),
	}
	_, err = s.caller.Call(nil, calls...)
	if err != nil {
		return common.Address{}, common.Address{}, common.Address{}, err
	}
	return t0Out.Addr, t1Out.Addr, facOut.Addr, nil
}

func (s *MulticallService) FetchV3PoolFee(poolAddr common.Address) (*big.Int, error) {
	poolContract, err := multicall.NewContract(v3PoolAbiString, poolAddr.Hex())
	if err != nil {
		return nil, err
	}
	feeOut := new(feeOutput)
	calls := []*multicall.Call{
		poolContract.NewCall(feeOut, "fee"),
	}
	_, err = s.caller.Call(nil, calls...)
	if err != nil {
		return nil, err
	}
	return feeOut.Fee, nil
}

func (s *MulticallService) FetchV3PoolState(poolAddr common.Address) (common.Address, common.Address, *big.Int, *big.Int, *big.Int, error) {
	poolContract, err := multicall.NewContract(v3PoolAbiString, poolAddr.Hex())
	if err != nil {
		return common.Address{}, common.Address{}, nil, nil, nil, err
	}

	t0Out, t1Out, s0Out, liqOut := new(tokenOutput), new(tokenOutput), new(v3Slot0Output), new(v3LiquidityOutput)
	calls := []*multicall.Call{
		poolContract.NewCall(t0Out, "token0"),
		poolContract.NewCall(t1Out, "token1"),
		poolContract.NewCall(s0Out, "slot0"),
		poolContract.NewCall(liqOut, "liquidity"),
	}
	_, err = s.caller.Call(nil, calls...)
	if err != nil {
		return common.Address{}, common.Address{}, nil, nil, nil, err
	}
	return t0Out.Addr, t1Out.Addr, s0Out.SqrtPriceX96, s0Out.Tick, liqOut.Liquidity, nil
}

func (s *MulticallService) GetTokenMetadataBatch(tokenAddresses []common.Address) map[string]TokenMetadata {
	var calls []*multicall.Call
	type symbolOutput struct{ Symbol string }
	type decimalsOutput struct{ Decimals uint8 }
	type callInfo struct {
		address common.Address
		symOut  *symbolOutput
		decOut  *decimalsOutput
	}
	var callInfos []callInfo
	uncachedTokens := make(map[string]bool)
	finalMetadata := make(map[string]TokenMetadata)

	for _, addr := range tokenAddresses {
		addrHex := strings.ToLower(addr.Hex())
		if data, ok := s.tokenCache.Get(addrHex); ok {
			finalMetadata[addrHex] = data
		} else {
			if _, alreadyQueued := uncachedTokens[addrHex]; !alreadyQueued {
				uncachedTokens[addrHex] = true
				contract, _ := multicall.NewContract(erc20AbiString, addr.Hex())
				symOut, decOut := new(symbolOutput), new(decimalsOutput)
				calls = append(calls, contract.NewCall(symOut, "symbol").AllowFailure())
				calls = append(calls, contract.NewCall(decOut, "decimals").AllowFailure())
				callInfos = append(callInfos, callInfo{address: addr, symOut: symOut, decOut: decOut})
			}
		}
	}

	if len(calls) == 0 {
		return finalMetadata
	}

	_, err := s.caller.Call(nil, calls...)
	if err != nil {
		log.Printf("Multicall metadata aggregate error: %v", err)
	}

	for i, info := range callInfos {
		symCall := calls[i*2]
		decCall := calls[i*2+1]
		addrHex := strings.ToLower(info.address.Hex())
		symbol := "UNKN"
		var decimals uint8 = 18

		if !symCall.Failed {
			symbol = info.symOut.Symbol
		}
		if !decCall.Failed {
			decimals = info.decOut.Decimals
		}

		metadata := TokenMetadata{Symbol: symbol, Decimals: decimals}
		s.tokenCache.Add(addrHex, metadata)
		finalMetadata[addrHex] = metadata
	}

	return finalMetadata
}

func (s *MulticallService) CacheTokenMetadata(address string, symbol string, decimals uint8) {
	s.tokenCache.Add(strings.ToLower(address), TokenMetadata{Symbol: symbol, Decimals: decimals})
}
