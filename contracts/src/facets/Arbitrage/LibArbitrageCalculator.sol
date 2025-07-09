// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUniswapV2Pair} from "../../interfaces/IUniswapV2.sol";
import {IUniswapV3Pool} from "../../interfaces/IUniswapV3.sol";
import {LibExchangeUtils} from "../ExchangeHelper/LibExchangeUtils.sol";
import {ExchangeCategory} from "../ExchangeHelper/IExchangeHelper.sol";
import {PoolsDoNotShareToken, PoolInfoQueryFailed, ReserveCalculationError} from "./IArbitrageV2.sol";

library LibArbitrageCalculator {
    // Heuristic: Loan amount will be a percentage of the smaller reserve of the two pools.
    // 100 BPS = 1%. This is a conservative value to minimize slippage.
    uint256 constant LOAN_PERCENTAGE_BPS = 100;

    struct PoolInfo {
        ExchangeCategory category;
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
    }

    /**
     * @notice Analyzes a pool to get its type, tokens, and reserves.
     * @dev Abstracts the differences between V2 and V3 pools for easier analysis.
     */
    function getPoolInfo(address poolAddress) internal view returns (PoolInfo memory) {
        (ExchangeCategory category, bool success) = LibExchangeUtils.detectExchangeType(poolAddress);
        if (!success || category == ExchangeCategory.Unknown) revert PoolInfoQueryFailed();

        if (category == ExchangeCategory.UniswapV2) {
            IUniswapV2Pair pair = IUniswapV2Pair(poolAddress);
            (uint112 r0, uint112 r1, ) = pair.getReserves();
            return PoolInfo(category, pair.token0(), pair.token1(), r0, r1);
        } else if (category == ExchangeCategory.UniswapV3) {
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            // V3 "reserves" are not stored directly. We use liquidity as a proxy for our heuristic.
            // A more advanced implementation would calculate virtual reserves based on the current tick.
            uint128 liquidity = pool.liquidity();
            return PoolInfo(category, pool.token0(), pool.token1(), liquidity, liquidity);
        }
        revert PoolInfoQueryFailed();
    }

    /**
     * @notice Given two pools, finds the common pivot token and the two outer tokens.
     * @return tokenOuterA The non-pivot token from the first pool.
     * @return tokenOuterB The non-pivot token from the second pool.
     * @return pivotToken The token shared between both pools.
     */
    function findArbitragePath(PoolInfo memory infoA, PoolInfo memory infoB)
        internal
        pure
        returns (address tokenOuterA, address tokenOuterB, address pivotToken)
    {
        if (infoA.token0 == infoB.token0 || infoA.token0 == infoB.token1) {
            pivotToken = infoA.token0;
            tokenOuterA = infoA.token1;
            tokenOuterB = (pivotToken == infoB.token0) ? infoB.token1 : infoB.token0;
        } else if (infoA.token1 == infoB.token0 || infoA.token1 == infoB.token1) {
            pivotToken = infoA.token1;
            tokenOuterA = infoA.token0;
            tokenOuterB = (pivotToken == infoB.token0) ? infoB.token1 : infoB.token0;
        } else {
            revert PoolsDoNotShareToken();
        }
    }

    /**
     * @notice Calculates the flash loan amount based on a percentage of the relevant reserve.
     */
    function calculateLoanAmount(PoolInfo memory info, address loanToken) internal pure returns (uint256) {
        uint256 reserve = (info.token0 == loanToken) ? info.reserve0 : info.reserve1;
        if (reserve == 0) revert ReserveCalculationError();
        return (reserve * LOAN_PERCENTAGE_BPS) / 10000;
    }

    /**
     * @notice Simulates a swap to get an estimated output amount.
     * @dev This is a simplified on-chain quotation function. Production versions would be more complex.
     */
    function quote(uint256 amountIn, PoolInfo memory pool, address tokenIn) internal pure returns (uint256 amountOut) {
        if (pool.category == ExchangeCategory.UniswapV2) {
            uint256 reserveIn = (pool.token0 == tokenIn) ? pool.reserve0 : pool.reserve1;
            uint256 reserveOut = (pool.token0 == tokenIn) ? pool.reserve1 : pool.reserve0;
            
            uint256 amountInWithFee = amountIn * 997;
            uint256 numerator = amountInWithFee * reserveOut;
            uint256 denominator = (reserveIn * 1000) + amountInWithFee;
            if (denominator == 0) return 0;
            return numerator / denominator;
        } else if (pool.category == ExchangeCategory.UniswapV3) {
            // V3 quoting is very complex. We use a simple ratio of liquidity as a rough heuristic.
            // This is NOT precise and should be replaced with a call to a Quoter contract for production.
            uint256 reserveIn = (pool.token0 == tokenIn) ? pool.reserve0 : pool.reserve1;
            uint256 reserveOut = (pool.token0 == tokenIn) ? pool.reserve1 : pool.reserve0;
            if (reserveIn == 0) return 0;
            // This is a very rough estimate and ignores the price curve.
            return (amountIn * reserveOut) / reserveIn;
        }
        return 0;
    }
}