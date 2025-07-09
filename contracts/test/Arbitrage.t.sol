// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ArbitrageExecutor, SwapStep} from "../src/ArbitrageExecutor.sol";
import {SwapLib} from "../src/lib/SwapLib.sol";
import {IERC20} from "@uniswap/v2-periphery/contracts/interfaces/IERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract ArbitrageTest is Test {
    // --- Constants for Arbitrum Forking ---
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    // Routers
    address constant SUSHISWAP_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    // Camelot is a major Algebra-based DEX on Arbitrum
    address constant CAMELOT_ROUTER = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;

    ArbitrageExecutor executor;

    function setUp() public {
        executor = new ArbitrageExecutor();
    }

    // =========================================================================
    //                        EXTENSIVE ARBITRAGE TESTS
    // =========================================================================

    /**
     * @notice Tests a classic 3-step triangular arbitrage path.
     * @dev Path: WETH -> USDC (UniV3) -> DAI (Sushi) -> WETH (Camelot)
     * The goal is to end with more WETH than we started with.
     */
    function test_TriangularArbitrage_WETH_USDC_DAI_WETH() public {
        uint256 initialWethAmount = 1 ether;
        deal(WETH, address(executor), initialWethAmount);

        SwapStep[] memory steps = new SwapStep[](3);

        // Step 1: Swap WETH for USDC on Uniswap V3
        steps[0] = SwapStep({
            params: SwapLib.SwapParams({
                dexType: SwapLib.DEX_TYPE.UNISWAP_V3_ROUTER,
                target: UNISWAP_V3_ROUTER,
                tokenIn: WETH,
                tokenOut: USDC,
                amountIn: 0, // Will be set dynamically
                fee: 3000,   // 0.3%
                sqrtPriceLimitX96: 0
            }),
            amountOutMin: 0 // For testing, we don't care about slippage
        });

        // Step 2: Swap USDC for DAI on SushiSwap
        steps[1] = SwapStep({
            params: SwapLib.SwapParams({
                dexType: SwapLib.DEX_TYPE.UNISWAP_V2_ROUTER,
                target: SUSHISWAP_ROUTER,
                tokenIn: USDC,
                tokenOut: DAI,
                amountIn: 0,
                fee: 0,
                sqrtPriceLimitX96: 0
            }),
            amountOutMin: 0
        });

        // Step 3: Swap DAI back to WETH on Camelot (Algebra-based)
        steps[2] = SwapStep({
            params: SwapLib.SwapParams({
                // NOTE: Camelot's router uses the V2 interface for swaps
                dexType: SwapLib.DEX_TYPE.UNISWAP_V2_ROUTER,
                target: CAMELOT_ROUTER,
                tokenIn: DAI,
                tokenOut: WETH,
                amountIn: 0,
                fee: 0,
                sqrtPriceLimitX96: 0
            }),
            amountOutMin: 0
        });

        console.log("--- Executing Triangular Arbitrage ---");
        console.log("Initial WETH:", initialWethAmount);

        uint256 finalWethAmount = executor.executeTrade(steps, initialWethAmount);

        console.log("Final WETH:  ", finalWethAmount);

        // This is the core assertion for an arbitrage test.
        // In a real scenario, this may or may not be profitable.
        // For this test, we only assert that the execution completes.
        assertTrue(finalWethAmount > 0, "Arbitrage execution should result in some WETH");
    }
}
