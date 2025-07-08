// =================================================================================
// FILE PATH: smart-contracts/test/facets/ArbitrageFacet.t.sol
// =================================================================================
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// =================================================================================
// CORRECTED TEST FILE
// This test now inherits from DiamondTest and follows the established pattern.
// =================================================================================

import {DiamondTest} from "../DiamondTest.sol"; // Assumes DiamondTest.sol is in the parent directory.
import {ArbitrageFacet} from "../../contracts/facets/ArbitrageFacet.sol";
import {IDiamondCut} from "../../contracts/interfaces/IDiamondCut.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Minimal interface definitions needed for the test, consistent with your project.
namespace Arbitrage {
    enum SwapType { UniswapV2, UniswapV3 }

    struct SwapData {
        address pool;
        address tokenIn;
        address tokenOut;
        SwapType swapType;
    }
}


contract ArbitrageFacetTest is DiamondTest {
    // --- State Variables ---
    ArbitrageFacet arbitrageFacet; // The facet implementation contract

    // --- Mainnet Addresses (for forking) ---
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant UNISWAP_V2_DAI_WETH = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33EB11;
    address internal constant AAVE_LENDING_POOL_PROVIDER = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address internal constant DAI_WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    function setUp() public virtual override {
        // 1. Call the parent setUp() to deploy the base diamond.
        super.setUp();

        // 2. Deploy the facet implementation contract.
        arbitrageFacet = new ArbitrageFacet();

        // 3. Prepare the facet cut to add the ArbitrageFacet to the diamond.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = arbitrageFacet.executeAaveArbitrage.selector;
        
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(arbitrageFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });

        // 4. Execute the diamond cut to add the new facet.
        vm.prank(owner);
        IDiamondCut(diamond).diamondCut(cut, address(0), "");

        // --- Label addresses for easier debugging ---
        vm.label(WETH, "WETH");
        vm.label(DAI, "DAI");
        vm.label(address(diamond), "DiamondProxy");
        vm.label(address(arbitrageFacet), "ArbitrageFacetImpl");
    }

    // --- Test Cases ---

    /**
     * @notice Tests the full arbitrage flow through the diamond proxy on a mainnet fork.
     * @dev This ensures the diamond cut is correct and the core logic is mechanically sound.
     */
    function test_executeAaveArbitrage_Flow_Through_Diamond() public {
        // --- Arrange: Setup the arbitrage parameters ---
        uint256 flashLoanAmount = 100_000 * 1e18; // Flash loan 100,000 DAI

        Arbitrage.SwapData memory legA = Arbitrage.SwapData(UNISWAP_V2_DAI_WETH, DAI, WETH, Arbitrage.SwapType.UniswapV2);
        Arbitrage.SwapData memory legB = Arbitrage.SwapData(UNISWAP_V2_DAI_WETH, WETH, DAI, Arbitrage.SwapType.UniswapV2);

        // --- Act & Assert ---

        // Fund the Diamond contract directly with a fee reserve.
        // The profit/loss will accrue to the diamond itself.
        uint256 feeReserve = 100 * 1e18; // 100 DAI to cover fees
        deal(DAI, address(diamond), feeReserve);

        uint256 balanceBefore = IERC20(DAI).balanceOf(address(diamond));
        console.log("DAI balance of Diamond before arbitrage: %s", balanceBefore);

        // Execute the arbitrage by calling the function ON THE DIAMOND PROXY.
        // The call is delegated to our ArbitrageFacet implementation.
        // No prank is needed as the function should be externally callable by the bot.
        ArbitrageFacet(diamond).executeAaveArbitrage(
            legA,
            legB,
            flashLoanAmount,
            AAVE_LENDING_POOL_PROVIDER
        );

        uint256 balanceAfter = IERC20(DAI).balanceOf(address(diamond));
        console.log("DAI balance of Diamond after arbitrage: %s", balanceAfter);

        // Assert that we didn't lose our initial fee reserve.
        // A profitable arbitrage would result in balanceAfter > balanceBefore.
        assertTrue(balanceAfter >= feeReserve, "Arbitrage resulted in a loss of the initial fee reserve.");
    }
}
