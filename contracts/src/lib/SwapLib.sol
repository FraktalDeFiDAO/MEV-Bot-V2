// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUniswapV2Pair, IERC20, IUniswapV2Router02} from "../interfaces/IUniswapV2.sol";
import {IUniswapV3Pool, ISwapRouter} from "../interfaces/IUniswapV3.sol";
import {DirectionalFeeData} from "../interfaces/IAlgebra.sol";

library SwapLib {
    enum DEX_TYPE {
        // Direct Pool Swaps (most gas efficient)
        UNISWAP_V2_POOL,
        UNISWAP_V3_POOL,
        ALGEBRA_INTEGRAL,
        ALGEBRA_INTEGRAL_DIR_FEE,
        ALGEBRA_V1_9,
        ALGEBRA_V1_9_DIR_FEE,
        // Router Swaps (more robust, handles fee-on-transfer)
        UNISWAP_V2_ROUTER,
        UNISWAP_V3_ROUTER
    }

    error DeadPair();
    error InvalidRouter();

    struct SwapParams {
        DEX_TYPE dexType;
        address target; // Pool or Router address
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee; // Only for V3 Router swaps
        uint160 sqrtPriceLimitX96; // For direct V3-style swaps
    }

    function executeSwap(SwapParams memory params) internal {
        DEX_TYPE dexType = params.dexType;

        if (dexType == DEX_TYPE.UNISWAP_V2_POOL) {
            _swapUniswapV2Pool(params);
        } else if (dexType == DEX_TYPE.UNISWAP_V2_ROUTER) {
            _swapUniswapV2Router(params);
        } else if (dexType == DEX_TYPE.UNISWAP_V3_ROUTER) {
            _swapUniswapV3Router(params);
        } else if (
            dexType == DEX_TYPE.UNISWAP_V3_POOL ||
            dexType == DEX_TYPE.ALGEBRA_INTEGRAL ||
            dexType == DEX_TYPE.ALGEBRA_INTEGRAL_DIR_FEE ||
            dexType == DEX_TYPE.ALGEBRA_V1_9 ||
            dexType == DEX_TYPE.ALGEBRA_V1_9_DIR_FEE
        ) {
            _swapV3LikePool(params);
        } else {
            revert("SwapLib: Invalid DEX_TYPE");
        }
    }

    function _swapUniswapV2Pool(SwapParams memory params) private {
        IUniswapV2Pair pair = IUniswapV2Pair(params.target);
        (uint112 r0, uint112 r1, ) = pair.getReserves();
        if (r0 == 0 && r1 == 0) revert DeadPair();

        address token0 = pair.token0();
        (uint amount0Out, uint amount1Out) = params.tokenIn == token0 ? (uint(0), uint(1)) : (uint(1), uint(0));
        
        IERC20(params.tokenIn).transfer(params.target, params.amountIn);
        pair.swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _swapV3LikePool(SwapParams memory params) private {
        IUniswapV3Pool pool = IUniswapV3Pool(params.target);
        bool zeroForOne = params.tokenIn == pool.token0();
        bytes memory data;

        if (params.dexType == DEX_TYPE.ALGEBRA_INTEGRAL_DIR_FEE || params.dexType == DEX_TYPE.ALGEBRA_V1_9_DIR_FEE) {
            data = abi.encode(DirectionalFeeData({payer: address(this)}));
        }

        pool.swap(address(this), zeroForOne, int256(params.amountIn), params.sqrtPriceLimitX96, data);
    }

    function _swapUniswapV2Router(SwapParams memory params) private {
        IUniswapV2Router02 router = IUniswapV2Router02(params.target);
        if (address(router) == address(0)) revert InvalidRouter();

        address[] memory path = new address[](2);
        path[0] = params.tokenIn;
        path[1] = params.tokenOut;

        // Use the more robust function that supports fee-on-transfer tokens.
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(params.amountIn, 0, path, address(this), block.timestamp);
    }

    function _swapUniswapV3Router(SwapParams memory params) private {
        ISwapRouter router = ISwapRouter(params.target);
        if (address(router) == address(0)) revert InvalidRouter();

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: params.amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        router.exactInputSingle(swapParams);
    }
}
