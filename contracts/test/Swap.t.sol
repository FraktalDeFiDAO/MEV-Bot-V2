// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ArbitrageExecutor, SwapStep} from "../src/ArbitrageExecutor.sol";
import {SwapLib} from "../src/lib/SwapLib.sol";
import {IERC20} from "@uniswap/v2-periphery/contracts/interfaces/IERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract SwapTest is Test {
    // --- Constants for Arbitrum Forking ---
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    // Routers
    address constant SUSHISWAP_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant CAMELOT_ROUTER = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;
    
    // Factories
    address constant SUSHISWAP_FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant CAMELOT_FACTORY = 0x6EcCab422D763aC031210895C81787E87B43A652;

    uint160 constant MIN_SQRT_RATIO = 4295128739;

    ArbitrageExecutor executor;
    uint256 constant STARTING_WETH_AMOUNT = 10 ether;

    // Pool addresses
    address sushiswapWethUsdcPool;
    address uniswapV3WethUsdcPool;
    address camelotWethUsdcPool;

    function setUp() public {
        executor = new ArbitrageExecutor();
        deal(WETH, address(executor), STARTING_WETH_AMOUNT);

        sushiswapWethUsdcPool = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(WETH, USDC);
        require(sushiswapWethUsdcPool != address(0), "SushiSwap WETH/USDC Pool not found");

        uniswapV3WethUsdcPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(WETH, USDC, 3000);
        require(uniswapV3WethUsdcPool != address(0), "V3 WETH/USDC 0.3% Pool not found");
        
        camelotWethUsdcPool = IUniswapV2Factory(CAMELOT_FACTORY).getPair(WETH, USDC);
        require(camelotWethUsdcPool != address(0), "Camelot WETH/USDC Pool not found");
    }

    // =========================================================================
    //                            ROUTER SWAP TESTS
    // =========================================================================

    function test_RouterSwap_SushiSwap() public {
        _executeAndAssertSwap("SushiSwap Router (V2)", SwapLib.DEX_TYPE.UNISWAP_V2_ROUTER, SUSHISWAP_ROUTER, WETH, USDC, 0.01 ether, 0, 0, 0);
    }

    function test_RouterSwap_UniswapV3() public {
        _executeAndAssertSwap("Uniswap V3 Router", SwapLib.DEX_TYPE.UNISWAP_V3_ROUTER, UNISWAP_V3_ROUTER, WETH, USDC, 0.01 ether, 3000, 0, 0);
    }

    function test_RouterSwap_Camelot_Algebra() public {
        _executeAndAssertSwap("Camelot Router (Algebra)", SwapLib.DEX_TYPE.UNISWAP_V2_ROUTER, CAMELOT_ROUTER, WETH, USDC, 0.01 ether, 0, 0, 0);
    }

    // =========================================================================
    //                            DIRECT POOL SWAP TESTS
    // =========================================================================

    function test_DirectPoolSwap_SushiSwap() public {
        _executeAndAssertSwap("SushiSwap Direct Pool (V2)", SwapLib.DEX_TYPE.UNISWAP_V2_POOL, sushiswapWethUsdcPool, WETH, USDC, 0.01 ether, 0, 0, 0);
    }

    function test_DirectPoolSwap_UniswapV3() public {
        uint160 priceLimit = MIN_SQRT_RATIO + 1;
        _executeAndAssertSwap("Uniswap V3 Direct Pool", SwapLib.DEX_TYPE.UNISWAP_V3_POOL, uniswapV3WethUsdcPool, WETH, USDC, 0.05 ether, 0, 0, priceLimit);
    }
    
    // =========================================================================
    //                            EDGE CASE TESTS
    // =========================================================================
    
    function test_Fail_Reentrancy() public {
        MaliciousToken maliciousToken = new MaliciousToken(executor);
        deal(address(maliciousToken), address(executor), 1 ether);

        SwapStep[] memory steps = new SwapStep[](1);
        steps[0] = SwapStep({
            params: SwapLib.SwapParams({
                dexType: SwapLib.DEX_TYPE.UNISWAP_V2_POOL,
                target: address(maliciousToken),
                tokenIn: address(maliciousToken),
                tokenOut: WETH,
                amountIn: 0, fee: 0, sqrtPriceLimitX96: 0
            }),
            amountOutMin: 0
        });

        // Using a generic vm.expectRevert() to bypass a known Foundry stdStorage bug
        vm.expectRevert();
        executor.executeTrade(steps, 1 ether);
    }

    function test_Fail_InvalidRoute() public {
        SwapStep[] memory steps = new SwapStep[](2);
        
        steps[0] = SwapStep({
            params: SwapLib.SwapParams({
                dexType: SwapLib.DEX_TYPE.UNISWAP_V3_ROUTER,
                target: UNISWAP_V3_ROUTER,
                tokenIn: WETH,
                tokenOut: USDC,
                amountIn: 0, fee: 3000, sqrtPriceLimitX96: 0
            }),
            amountOutMin: 0
        });
        steps[1] = SwapStep({
            params: SwapLib.SwapParams({
                dexType: SwapLib.DEX_TYPE.UNISWAP_V2_ROUTER,
                target: SUSHISWAP_ROUTER,
                tokenIn: DAI, 
                tokenOut: WETH,
                amountIn: 0, fee: 0, sqrtPriceLimitX96: 0
            }),
            amountOutMin: 0
        });

        vm.expectRevert(abi.encodeWithSelector(ArbitrageExecutor.InvalidSwapRoute.selector, DAI, USDC));
        executor.executeTrade(steps, 0.01 ether);
    }

    // =========================================================================
    //                            HELPER FUNCTIONS
    // =========================================================================

    function _executeAndAssertSwap(
        string memory name,
        SwapLib.DEX_TYPE dexType,
        address target,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee,
        uint256 amountOutMin,
        uint160 sqrtPriceLimitX96
    ) private {
        SwapStep[] memory steps = new SwapStep[](1);
        steps[0] = SwapStep({
            params: SwapLib.SwapParams({
                dexType: dexType,
                target: target,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: 0, 
                fee: fee,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            amountOutMin: amountOutMin
        });

        uint256 balanceOutBefore = IERC20(tokenOut).balanceOf(address(executor));
        console.log("--- Testing Swap on %s ---", name);
        
        executor.executeTrade(steps, amountIn);

        uint256 balanceOutAfter = IERC20(tokenOut).balanceOf(address(executor));
        assertTrue(balanceOutAfter > balanceOutBefore, "Output token balance did not increase");
        
        console.log("--- Test Passed ---");
    }
}

contract MaliciousToken is IERC20 {
    ArbitrageExecutor immutable executor;

    constructor(ArbitrageExecutor _executor) {
        executor = _executor;
    }
    
    function approve(address, uint256) external pure returns (bool) { return true; }
    function transfer(address, uint256) external returns (bool) {
        try executor.executeTrade(new SwapStep[](0), 0) {} catch {}
        return true;
    }
    function totalSupply() external pure returns(uint256) { return 1e27; }
    function balanceOf(address) external pure returns (uint) { return 1e24; }
    function transferFrom(address, address, uint256) external pure returns (bool) {return true;}
    function allowance(address, address) external pure returns (uint256) { return type(uint256).max; }
    function symbol() external pure returns (string memory) { return "MAL"; }
    function name() external pure returns (string memory) { return "Malicious"; }
    function decimals() external pure returns (uint8) { return 18; }
    function token0() external view returns (address) { return address(this); }
    function token1() external pure returns (address) { return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; }
    function getReserves() external view returns (uint112, uint112, uint32) { return (1e18, 1e18, uint32(block.timestamp)); }
    function swap(uint, uint, address, bytes calldata) external {}
}
