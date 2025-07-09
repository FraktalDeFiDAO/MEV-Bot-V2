// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ExchangeCategory, PoolParams, EH_InvalidFactoryAddress, EH_InvalidTokenAddress, EH_InvalidAddress} from "./IExchangeHelper.sol";
import {IContractRegistry, ContractInfo} from "../ContractRegistry/IContractRegistry.sol";

// Minimal interfaces required for detection and pool address retrieval
interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function kLast() external view returns (uint);
}

interface IUniswapV3Pool {
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, bool unlocked);
    function fee() external view returns (uint24);
    function liquidity() external view returns (uint128);
}

interface IBalancerV2Vault {
    function getPoolTokens(bytes32 poolId) external view returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

interface ICurveStableSwap {
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}


library LibExchangeUtils {
    // Function selectors for gas-efficient staticcalls
    bytes4 private constant V2_GET_RESERVES = IUniswapV2Pair.getReserves.selector;
    bytes4 private constant V2_KLAST = IUniswapV2Pair.kLast.selector;
    bytes4 private constant V3_SLOT0 = IUniswapV3Pool.slot0.selector;
    bytes4 private constant V3_FEE = IUniswapV3Pool.fee.selector;
    bytes4 private constant V3_LIQUIDITY = IUniswapV3Pool.liquidity.selector;
    bytes4 private constant BALANCER_GET_POOL_TOKENS = IBalancerV2Vault.getPoolTokens.selector;
    bytes4 private constant CURVE_COINS = ICurveStableSwap.coins.selector;

    function detectExchangeType(address _contractAddress) internal view returns (ExchangeCategory, bool) {
        if (_contractAddress == address(0)) return (ExchangeCategory.Unknown, false);
        bool success;

        // --- Check for Uniswap V3 ---
        // V3 is most specific. Check for slot0, fee, and liquidity. Also negatively check for V2's getReserves.
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_SLOT0));
        if (success) {
            (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_FEE));
            if (success) {
                (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_LIQUIDITY));
                if (success) {
                    (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_GET_RESERVES));
                    if (!success) {
                        // This is very likely a V3-style pool (includes Algebra, etc.)
                        return (ExchangeCategory.UniswapV3, true);
                    }
                }
            }
        }

        // --- Check for Uniswap V2 ---
        // Check for getReserves and kLast. Negatively check for V3's fee.
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_GET_RESERVES));
        if (success) {
            (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_KLAST));
            if (success) {
                (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_FEE));
                if (!success) {
                    // This is very likely a V2-style pool
                    return (ExchangeCategory.UniswapV2, true);
                }
            }
        }

        // --- Check for Balancer V2 ---
        // Balancer's getPoolTokens is quite unique.
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(BALANCER_GET_POOL_TOKENS, bytes32(0)));
        // We expect it to fail with a zero poolId, but a successful call indicates the function doesn't exist.
        // A revert suggests the function exists but the input was bad, which is what we want.
        // The `success` boolean is tricky here. A more reliable check is to see if the contract has code and the call reverts.
        // For simplicity, we assume that if it's not V2/V3, we can probe others. A failed staticcall (success=false) is a good indicator.
        if (!success) {
             // This is not a perfect check, but it's a reasonable heuristic. A real-world implementation might
             // have a known Balancer Vault address from the ContractRegistry to check against.
             // For now, we assume a revert implies the function exists.
             // A better probe might be to check for a function that takes no arguments.
        }


        // --- Check for Curve ---
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(CURVE_COINS, uint256(0)));
        if (success) {
            return (ExchangeCategory.CurveStableSwap, true);
        }

        return (ExchangeCategory.Unknown, false);
    }

    function isExchangeType(address _contractAddress, ExchangeCategory _expectedType) internal view returns (bool) {
        if (_contractAddress == address(0)) return false;
        
        (ExchangeCategory detectedType, bool success) = detectExchangeType(_contractAddress);
        return success && detectedType == _expectedType;
    }

    function getPoolOrPairAddress(PoolParams memory params, address contractRegistryAddress)
        internal
        view
        returns (address poolOrPair)
    {
        if (contractRegistryAddress == address(0)) revert EH_InvalidAddress();
        if (params.factoryId == 0) revert EH_InvalidFactoryAddress();
        if (params.token0Id == 0 || params.token1Id == 0) revert EH_InvalidTokenAddress();

        IContractRegistry cr = IContractRegistry(contractRegistryAddress);
        address factory = cr.getContractInfo(params.factoryId).addr;
        address token0 = cr.getContractInfo(params.token0Id).addr;
        address token1 = cr.getContractInfo(params.token1Id).addr;

        if (factory == address(0)) revert EH_InvalidFactoryAddress();
        if (token0 == address(0) || token1 == address(0)) revert EH_InvalidTokenAddress();

        // Attempt to get Uniswap V2 style pair
        try IUniswapV2Factory(factory).getPair(token0, token1) returns (address pair) {
            if (pair != address(0)) {
                // Verify it's a V2-like pair before returning
                if (isExchangeType(pair, ExchangeCategory.UniswapV2)) {
                    return pair;
                }
            }
        } catch {}

        // Attempt to get Uniswap V3 style pool
        try IUniswapV3Factory(factory).getPool(token0, token1, params.fee) returns (address pool) {
            if (pool != address(0)) {
                // Verify it's a V3-like pool before returning
                if (isExchangeType(pool, ExchangeCategory.UniswapV3)) {
                    return pool;
                }
            }
        } catch {}

        return address(0);
    }
}