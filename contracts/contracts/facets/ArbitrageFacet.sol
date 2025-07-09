// =================================================================================
// FILE PATH: smart-contracts/test/facets/ArbitrageFacet.t.sol
// =================================================================================
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// CORRECTED: Import paths are now correct relative to the 'smart-contracts' root.
import {DiamondTest} from "test/DiamondTest.sol";
import {ArbitrageFacet, ActionSwapParams} from "facets/ArbitrageFacet.sol";
import {IDiamondCut} from "interfaces/IDiamondCut.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ArbitrageFacetTest is DiamondTest {
    ArbitrageFacet arbitrageFacet;

    // --- Mainnet Addresses (for forking) ---
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant UNISWAP_V2_DAI_WETH = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33EB11;

    function setUp() public virtual override {
        super.setUp();
        arbitrageFacet = new ArbitrageFacet();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = arbitrageFacet.executeAaveArbitrage.selector;
        
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(arbitrageFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.prank(owner);
        IDiamondCut(diamond).diamondCut(cut, address(0), "");

        vm.label(WETH, "WETH");
        vm.label(DAI, "DAI");
        vm.label(address(diamond), "DiamondProxy");
    }

    function test_executeAaveArbitrage_Flow_Through_Diamond() public {
        // --- Arrange ---
        uint256 flashLoanAmount = 100_000 * 1e18; // Flash loan 100,000 DAI
        uint256 minProfit = 1 * 1e16; // 0.01 DAI

        // Use the actual ActionSwapParams struct from your contract.
        ActionSwapParams memory legA = ActionSwapParams({
            pool: UNISWAP_V2_DAI_WETH,
            tokenIn: DAI,
            tokenOut: WETH,
            amountIn: flashLoanAmount, // The amount for the first leg is the loan amount
            amountOutMin: 0 // For tests, we can be lenient
        });

        ActionSwapParams memory legB = ActionSwapParams({
            pool: UNISWAP_V2_DAI_WETH,
            tokenIn: WETH,
            tokenOut: DAI,
            amountIn: 0, // This will be determined by the output of legA
            amountOutMin: flashLoanAmount + minProfit
        });

        // --- Act & Assert ---
        uint256 feeReserve = 100 * 1e18; // 100 DAI to cover fees
        deal(DAI, address(diamond), feeReserve);

        uint256 balanceBefore = IERC20(DAI).balanceOf(address(diamond));

        // Call the function with the correct signature on the Diamond Proxy.
        ArbitrageFacet(diamond).executeAaveArbitrage(
            DAI, // loanAsset
            flashLoanAmount,
            legA,
            legB,
            minProfit
        );

        uint256 balanceAfter = IERC20(DAI).balanceOf(address(diamond));

        // In a non-profitable test scenario, we just want to ensure we didn't lose our reserve.
        assertTrue(balanceAfter >= feeReserve, "Arbitrage resulted in a loss of the initial fee reserve.");
    }
}
