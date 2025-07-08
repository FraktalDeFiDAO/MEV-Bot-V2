// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SwapLib} from "./lib/SwapLib.sol";
import {IERC20} from "@uniswap/v2-periphery/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IAlgebraSwapCallback, DirectionalFeeData} from "./interfaces/IAlgebra.sol";

struct SwapStep {
    SwapLib.SwapParams params;
    uint256 amountOutMin;
}

contract ArbitrageExecutor is
    Ownable,
    ReentrancyGuard,
    IUniswapV3SwapCallback,
    IAlgebraSwapCallback
{
    error SlippageProtectionViolated(uint256 amountOut, uint256 amountOutMin);
    error InvalidSwapRoute(address tokenIn, address expectedTokenIn);
    error InsufficientInputAmount();
    error CallbackInvalidated();
    error InvalidCaller(address caller, address expectedCaller);

    event TradeExecuted(
        address indexed caller,
        address initialToken,
        uint256 initialAmount,
        address finalToken,
        uint256 finalAmount
    );

    address private activePool;

    constructor() Ownable(msg.sender) {}

    function executeTrade(
        SwapStep[] calldata steps,
        uint256 initialAmount
    ) external nonReentrant onlyOwner returns (uint256 finalAmount) {
        if (steps.length == 0 || initialAmount == 0) revert InsufficientInputAmount();

        address initialToken = steps[0].params.tokenIn;
        uint256 currentAmount = initialAmount;

        for (uint256 i = 0; i < steps.length; ++i) {
            SwapStep calldata step = steps[i];
            address tokenIn = step.params.tokenIn;
            address tokenOut = step.params.tokenOut;

            address expectedTokenIn = (i == 0) ? initialToken : steps[i - 1].params.tokenOut;
            if (tokenIn != expectedTokenIn) revert InvalidSwapRoute(tokenIn, expectedTokenIn);
            
            SwapLib.SwapParams memory params = step.params;
            params.amountIn = currentAmount;

            IERC20(tokenIn).approve(params.target, currentAmount);

            uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

            if (params.dexType != SwapLib.DEX_TYPE.UNISWAP_V2_ROUTER && params.dexType != SwapLib.DEX_TYPE.UNISWAP_V3_ROUTER) {
                 activePool = params.target;
            }
           
            SwapLib.executeSwap(params);
            
            if (activePool != address(0)) {
                activePool = address(0);
            }

            uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
            uint256 amountOut = balanceAfter - balanceBefore;

            if (amountOut < step.amountOutMin) {
                revert SlippageProtectionViolated(amountOut, step.amountOutMin);
            }

            currentAmount = amountOut;
        }
        
        finalAmount = currentAmount;
        emit TradeExecuted(msg.sender, initialToken, initialAmount, steps[steps.length-1].params.tokenOut, finalAmount);
    }

    function _handleV3Callback(int256 amount0Delta, int256 amount1Delta) private {
        if (msg.sender != activePool) revert InvalidCaller(msg.sender, activePool);
        if(amount0Delta <= 0 && amount1Delta <= 0) revert CallbackInvalidated();

        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        address token = (amount0Delta > 0) ? pool.token0() : pool.token1();
        uint256 amount = (amount0Delta > 0) ? uint256(amount0Delta) : uint256(amount1Delta);
        
        IERC20(token).transfer(msg.sender, amount);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        _handleV3Callback(amount0Delta, amount1Delta);
    }

    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        _handleV3Callback(amount0Delta, amount1Delta);
        if (data.length > 0) {
            // Directional fee logic handled by pool via prior approval
        }
    }
    
    function withdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }

    receive() external payable {}
}
