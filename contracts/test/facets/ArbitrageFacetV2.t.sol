// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DiamondTest} from "../DiamondTest.sol";
import {IDiamondCut} from "src/interfaces/IDiamondCut.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "src/interfaces/IUniswapV2.sol";
import {IUniswapV2Router02} from "src/interfaces/IUniswapV2Router.sol";

// Facets to test
import {ArbitrageFacetV2, ArbitragePoolPair, ResolvedArbitragePath, NoProfitablePathFound} from "src/facets/Arbitrage/ArbitrageFacetV2.sol";
import {ArbitrageFacet} from "src/facets/Arbitrage/ArbitrageFacet.sol";
import {ArbitrageExecuted} from "src/facets/Arbitrage/ArbitrageFacet.sol"; // Event

// Other required contracts and libraries
import {LibAppStorage} from "src/libraries/LibAppStorage.sol";
import {IPoolAddressesProvider} from "src/interfaces/IPoolAddressesProvider.sol";
import {ActionSwapParams} from "src/facets/ExchangeHelper/LibExchangeActions.sol";

contract ArbitrageFacetV2Test is DiamondTest {
    // === Mainnet Addresses (for Forking) ===
    // Tokens
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // AAVE
    address internal constant AAVE_POOL_PROVIDER = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;

    // Uniswap V2
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Sushiswap
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    // === State Variables ===
    ArbitrageFacetV2 internal arbitrageFacetV2;
    ArbitrageFacet internal arbitrageFacet;

    address internal uniPairWethDai;
    address internal sushiPairWethDai;

    function setUp() public virtual override {
        super.setUp(); // Deploys the base diamond proxy

        // 1. Deploy Facet Implementations
        arbitrageFacetV2 = new ArbitrageFacetV2();
        arbitrageFacet = new ArbitrageFacet();

        // 2. Cut Facets into the Diamond
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](2);

        // Cut ArbitrageFacetV2
        bytes4[] memory v2Selectors = new bytes4[](2);
        v2Selectors[0] = arbitrageFacetV2.executePoolPairArbitrage.selector;
        v2Selectors[1] = arbitrageFacetV2.assessOpportunity.selector;
        cut[0] = IDiamondCut.FacetCut(address(arbitrageFacetV2), IDiamondCut.FacetCutAction.Add, v2Selectors);

        // Cut ArbitrageFacet (V1) - needed for execution logic
        bytes4[] memory v1Selectors = new bytes4[](3);
        v1Selectors[0] = arbitrageFacet.initialize.selector;
        v1Selectors[1] = arbitrageFacet.executeAaveArbitrage.selector;
        v1Selectors[2] = arbitrageFacet.executeOperation.selector; // The flash loan callback
        cut[1] = IDiamondCut.FacetCut(address(arbitrageFacet), IDiamondCut.FacetCutAction.Add, v1Selectors);

        // Perform the cut
        vm.prank(owner);
        IDiamondCut(diamond).diamondCut(cut, address(0), "");

        // 3. Initialize the ArbitrageFacet within the diamond's context
        vm.prank(owner);
        ArbitrageFacet(diamond).initialize(WETH, AAVE_POOL_PROVIDER, owner);

        // 4. Get LP Pair addresses
        uniPairWethDai = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(WETH, DAI);
        sushiPairWethDai = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(WETH, DAI);

        // 5. Label addresses for easier debugging
        vm.label(WETH, "WETH");
        vm.label(DAI, "DAI");
        vm.label(diamond, "DiamondProxy");
        vm.label(uniPairWethDai, "UNIV2_WETH_DAI");
        vm.label(sushiPairWethDai, "SUSHIV2_WETH_DAI");
    }

    /// @notice Skews the price on one DEX to create a testable arbitrage opportunity.
    function _createArbitrageOpportunity() internal {
        uint256 skewAmount = 500 * 1e18; // 500 WETH
        deal(WETH, address(this), skewAmount); // Give test contract WETH

        // Approve Uniswap Router to spend our WETH
        IERC20(WETH).approve(UNISWAP_V2_ROUTER, skewAmount);

        // Skew the price by swapping a large amount of WETH for DAI on Uniswap
        // This lowers the price of WETH on Uniswap relative to Sushiswap
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            skewAmount, 0, path, address(this), block.timestamp
        );
        console.log("Created arbitrage opportunity by selling %s WETH on Uniswap.", skewAmount / 1e18);
    }

    function test_assessOpportunity_revertsWhenNoProfit() public {
        // Arrange: Use the same pool for both A and B, so no opportunity exists.
        ArbitragePoolPair memory opportunity =
            ArbitragePoolPair({poolA: uniPairWethDai, poolB: uniPairWethDai, exchangeIdA: 0, exchangeIdB: 0});

        // Act & Assert: Expect a revert
        vm.expectRevert(NoProfitablePathFound.selector);
        ArbitrageFacetV2(diamond).assessOpportunity(opportunity);
    }

    function test_assessAndExecute_findsAndExecutesProfitableArbitrage() public {
        // === ARRANGE ===
        // 1. Create the price difference between the two pools
        _createArbitrageOpportunity();

        // 2. Define the opportunity for the facet
        ArbitragePoolPair[] memory opportunities = new ArbitragePoolPair[](1);
        opportunities[0] = ArbitragePoolPair({
            poolA: uniPairWethDai, // Where WETH is now cheaper
            poolB: sushiPairWethDai, // Where WETH is more expensive
            exchangeIdA: 0, // In a real system, these would be managed IDs
            exchangeIdB: 0
        });

        // === ACT & ASSERT (ASSESS) ===
        console.log("Assessing opportunity...");
        ResolvedArbitragePath memory path = ArbitrageFacetV2(diamond).assessOpportunity(opportunities[0]);

        assertTrue(path.profitable, "Path should be assessed as profitable");
        // We sold WETH on Uniswap, making it cheap. The correct path is to flash-loan WETH,
        // buy DAI on Sushiswap, then use the DAI to buy back more WETH on Uniswap.
        // Wait, the logic is simpler. Buy low, sell high.
        // The path should be: Loan DAI, buy cheap WETH on Uni, sell WETH for more DAI on Sushi.
        assertTrue(path.expectedProfit > 0, "Expected profit should be positive");
        console.log("Assessed profitable path with expected profit of %s", path.expectedProfit);

        // === ACT & ASSERT (EXECUTE) ===
        uint256 balanceBefore = IERC20(DAI).balanceOf(diamond);
        console.log("Diamond DAI balance before arbitrage: %s", balanceBefore);

        // We expect the final execution event to be emitted
        // We can't easily predict the profit due to slippage, so we check for the event broadly.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit ArbitrageExecuted(
            path.loanAsset,
            path.loanAmount,
            path.legB.tokenInId, // Intermediate token
            0, // amountIntermediateReceived (unknown)
            0, // amountLoanAssetRecovered (unknown)
            0, // profit (unknown)
            address(this) // initiator
        );

        // Execute the arbitrage
        console.log("Executing pool pair arbitrage...");
        ArbitrageFacetV2(diamond).executePoolPairArbitrage(opportunities);

        uint256 balanceAfter = IERC20(DAI).balanceOf(diamond);
        console.log("Diamond DAI balance after arbitrage: %s", balanceAfter);

        assertTrue(balanceAfter > balanceBefore, "DAI balance should increase after arbitrage");
        uint256 profit = balanceAfter - balanceBefore;
        console.log("Actual realized profit: %s DAI", profit);
        assertTrue(profit > 0, "Profit must be greater than zero");
    }
}
