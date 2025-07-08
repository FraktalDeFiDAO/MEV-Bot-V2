// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUniswapV2Pair} from "../../interfaces/IUniswapV2.sol";
import {IUniswapV3Pool} from "../../interfaces/IUniswapV3.sol";
import {TokenInfo} from "../TokenHelper/ITokenHelper.sol";
import {LibTokenHelper} from "../TokenHelper/LibTokenHelper.sol";
import {LibExchangeUtils} from "../ExchangeHelper/LibExchangeUtils.sol";
import {ExchangeCategory} from "../ExchangeHelper/IExchangeHelper.sol";
import {PoolsDoNotShareToken, PoolInfoQueryFailed, ReserveCalculationError} from "./IArbitrageV2.sol";

library LibArbitrageCalculator {
    // Heuristic: Loan amount will be 1% of the smaller reserve of the two pools.
    uint256 constant LOAN_PERCENTAGE_BPS = 100; // 100 BPS = 1%

    struct PoolInfo {
        ExchangeCategory category;
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
    }

    /**
     * @notice Analyzes a pool to get its type, tokens, and reserves.
     * @dev Abstracts the differences between V2 and V3 pools.
     */
    function getPoolInfo(address poolAddress) internal view returns (PoolInfo memory) {
        (ExchangeCategory category, bool success) = LibExchangeUtils.detectExchangeType(poolAddress);
        if (!success) revert PoolInfoQueryFailed();

        if (category == ExchangeCategory.UniswapV2) {
            IUniswapV2Pair pair = IUniswapV2Pair(poolAddress);
            (uint112 r0, uint112 r1, ) = pair.getReserves();
            return PoolInfo(category, pair.token0(), pair.token1(), r0, r1);
        } else if (category == ExchangeCategory.UniswapV3) {
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            // V3 "reserves" are not stored directly. We use liquidity as a proxy.
            // A more advanced implementation would calculate virtual reserves based on the current tick.
            // For a simple heuristic, we can use the pool's total liquidity.
            uint128 liquidity = pool.liquidity();
            return PoolInfo(category, pool.token0(), pool.token1(), liquidity, liquidity);
        }
        revert PoolInfoQueryFailed();
    }
    
    /**
     * @notice Given two pools, finds the common pivot token and the two outer tokens.
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
     * @notice Calculates the optimal flash loan amount based on a % of reserves.
     */
    function calculateLoanAmount(PoolInfo memory info, address loanToken) internal pure returns (uint256) {
        uint256 reserve = (info.token0 == loanToken) ? info.reserve0 : info.reserve1;
        if (reserve == 0) revert ReserveCalculationError();
        return (reserve * LOAN_PERCENTAGE_BPS) / 10000;
    }

    /**
     * @notice Simulates a swap to get an output amount.
     * @dev This is a simplified quotation function. Production versions would be more complex.
     */
    function quote(uint256 amountIn, PoolInfo memory pool) internal pure returns (uint256 amountOut) {
        if (pool.category == ExchangeCategory.UniswapV2) {
            // Simplified Uniswap V2 getAmountOut formula
            uint256 amountInWithFee = amountIn * 997;
            uint256 numerator = amountInWithFee * pool.reserve1;
            uint256 denominator = (pool.reserve0 * 1000) + amountInWithFee;
            return numerator / denominator;
        } else if (pool.category == ExchangeCategory.UniswapV3) {
            // V3 quoting is very complex (involving SqrtPriceMath).
            // For this on-chain example, we'll use a rough estimate.
            // A real implementation would either use a Quoter contract or a more detailed calculation.
            // Heuristic: amountOut is proportional to the ratio of "reserves" (using liquidity as a proxy).
            if (pool.reserve0 == 0) return 0;
            return (amountIn * pool.reserve1) / pool.reserve0;
        }
        return 0;
    }
}