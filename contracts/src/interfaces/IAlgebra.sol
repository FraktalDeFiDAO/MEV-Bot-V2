// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAlgebra
 * @notice Minimal interfaces for Algebra-family DEXs.
 * @dev Algebra DEXs (including Integral) are forks of Uniswap V3 but may have slight variations.
 * The core `swap` function signature remains compatible with `IUniswapV3Pool`.
 * This minimal interface is sufficient for swap execution and avoids pulling in entire non-standard libraries.
 */

// Callback interface for Algebra pools.
interface IAlgebraSwapCallback {
    /**
     * @notice Called to `msg.sender` after swapping token0 for token1 or token1 for token0.
     * @dev The call will be during IAlgebraPool.swap and the caller will be the pool contract.
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by the end of the swap.
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by the end of the swap.
     * @param data Any data passed through by the caller via the IAlgebraPool.swap call.
     */
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

// Minimal data structure for decoding callback data for directional fees.
struct DirectionalFeeData {
    address payer;
}
