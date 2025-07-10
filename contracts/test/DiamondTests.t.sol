// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title DiamondTests
 * @notice This is the single, consolidated test file for the entire diamond.
 * @dev It includes the abstract state setup contracts and the concrete test contracts.
 *      This structure resolves all "Identifier already declared" compiler errors by
 *      eliminating the problematic cross-file imports between test files.
 */

// =====================================================================================
//                       HELPER AND INTERFACE IMPORTS
// =====================================================================================
import "../src/interfaces/IDiamondCut.sol";
import "../src/facets/DiamondCutFacet.sol";
import "../src/facets/DiamondLoupeFacet.sol";
import "../src/facets/AccessControl/AccessControlFacet.sol";
import "../src/facets/Test1Facet.sol";
import "../src/facets/Test2Facet.sol";
import "../src/Diamond.sol";
import "../src/upgradeInitializers/DiamondInit.sol";
import "../src/upgradeInitializers/DiamondMultiInit.sol";
import "./HelperContract.sol";
import "./TestStates.sol";



// =====================================================================================
//                       CONCRETE TEST EXECUTION CONTRACTS
// =====================================================================================

contract TestDeployDiamond is StateDeployDiamond {
    function test1HasCorrectNumberOfFacets() public {
        assertEq(facetAddressList.length, 3);
    }

    function test2FacetsHaveCorrectSelectors() public {
        for (uint256 i = 0; i < facetAddressList.length; i++) {
            bytes4[] memory fromLoupeFacet = ILoupe.facetFunctionSelectors(facetAddressList[i]);
            bytes4[] memory fromGenSelectors = generateSelectors(facetNames[i]);
            assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
        }
    }

    function test3SelectorsAssociatedWithCorrectFacet() public {
        for (uint256 i = 0; i < facetAddressList.length; i++) {
            bytes4[] memory fromGenSelectors = generateSelectors(facetNames[i]);
            for (uint256 j = 0; j < fromGenSelectors.length; j++) {
                assertEq(facetAddressList[i], ILoupe.facetAddress(fromGenSelectors[j]));
            }
        }
    }
}

contract TestAddFacet1 is StateAddFacet1 {
    function test4AddTest1FacetFunctions() public {
        bytes4[] memory fromLoupeFacet = ILoupe.facetFunctionSelectors(address(test1Facet));
        bytes4[] memory fromGenSelectors = removeElement(bytes4(keccak256("supportsInterface(bytes4)")), generateSelectors("Test1Facet"));
        assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
    }

    function test5CanCallTest1FacetFunction() public {
        Test1Facet(address(diamond)).test1Func10();
    }

    function test6ReplaceSupportsInterfaceFunction() public {
        bytes4[] memory fromGenSelectors = new bytes4[](1);
        fromGenSelectors[0] = bytes4(keccak256("supportsInterface(bytes4)"));

        FacetCut[] memory cutTest1 = new FacetCut[](1);
        cutTest1[0] = FacetCut({
            facetAddress: address(test1Facet),
            action: FacetCutAction.Replace,
            functionSelectors: fromGenSelectors
        });
        ICut.diamondCut(cutTest1, address(0x0), "");
        assertEq(address(test1Facet), ILoupe.facetAddress(fromGenSelectors[0]));
    }
}

contract TestAddFacet2 is StateAddFacet2 {
    function test7AddTest2FacetFunctions() public {
        bytes4[] memory fromLoupeFacet = ILoupe.facetFunctionSelectors(address(test2Facet));
        bytes4[] memory fromGenSelectors = generateSelectors("Test2Facet");
        assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
    }

    function test8RemoveSomeTest2FacetFunctions() public {
        bytes4[] memory functionsToKeep = new bytes4[](5);
        functionsToKeep[0] = test2Facet.test2Func1.selector;
        functionsToKeep[1] = test2Facet.test2Func5.selector;
        functionsToKeep[2] = test2Facet.test2Func6.selector;
        functionsToKeep[3] = test2Facet.test2Func19.selector;
        functionsToKeep[4] = test2Facet.test2Func20.selector;

        bytes4[] memory selectors = ILoupe.facetFunctionSelectors(address(test2Facet));
        for (uint256 i = 0; i < functionsToKeep.length; i++) {
            selectors = removeElement(functionsToKeep[i], selectors);
        }

        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({facetAddress: address(0x0), action: FacetCutAction.Remove, functionSelectors: selectors});
        ICut.diamondCut(facetCut, address(0x0), "");

        bytes4[] memory fromLoupeFacet = ILoupe.facetFunctionSelectors(address(test2Facet));
        assertTrue(sameMembers(fromLoupeFacet, functionsToKeep));
    }

    function test9RemoveSomeTest1FacetFunctions() public {
        bytes4[] memory functionsToKeep = new bytes4[](3);
        functionsToKeep[0] = test1Facet.test1Func2.selector;
        functionsToKeep[1] = test1Facet.test1Func11.selector;
        functionsToKeep[2] = test1Facet.test1Func12.selector;

        bytes4[] memory selectors = ILoupe.facetFunctionSelectors(address(test1Facet));
        for (uint256 i = 0; i < functionsToKeep.length; i++) {
            selectors = removeElement(functionsToKeep[i], selectors);
        }

        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({facetAddress: address(0x0), action: FacetCutAction.Remove, functionSelectors: selectors});
        ICut.diamondCut(facetCut, address(0x0), "");

        bytes4[] memory fromLoupeFacet = ILoupe.facetFunctionSelectors(address(test1Facet));
        assertTrue(sameMembers(fromLoupeFacet, functionsToKeep));
    }

    function test10RemoveAllExceptDiamondCutAndFacetFunction() public {
        bytes4[] memory selectors = getAllSelectors(address(diamond));

        bytes4[] memory functionsToKeep = new bytes4[](2);
        functionsToKeep[0] = DiamondCutFacet.diamondCut.selector;
        functionsToKeep[1] = DiamondLoupeFacet.facets.selector;

        selectors = removeElement(functionsToKeep[0], selectors);
        selectors = removeElement(functionsToKeep[1], selectors);

        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({facetAddress: address(0x0), action: FacetCutAction.Remove, functionSelectors: selectors});
        ICut.diamondCut(facetCut, address(0x0), "");

        Facet[] memory facets = ILoupe.facets();
        bytes4[] memory testselector = new bytes4[](1);

        assertEq(facets.length, 2);
        assertEq(facets[0].facetAddress, address(diamondCutFacet));
        testselector[0] = functionsToKeep[0];
        assertTrue(sameMembers(facets[0].functionSelectors, testselector));

        assertEq(facets[1].facetAddress, address(diamondLoupeFacet));
        testselector[0] = functionsToKeep[1];
        assertTrue(sameMembers(facets[1].functionSelectors, testselector));
    }
}

contract TestCacheBug is StateCacheBug {
    function testNoCacheBug() public {
        bytes4[] memory fromLoupeSelectors = ILoupe.facetFunctionSelectors(address(test1Facet));

        assertTrue(containsElement(fromLoupeSelectors, selectors[0]));
        assertTrue(containsElement(fromLoupeSelectors, selectors[1]));
        assertTrue(containsElement(fromLoupeSelectors, selectors[2]));
        assertTrue(containsElement(fromLoupeSelectors, selectors[3]));
        assertTrue(containsElement(fromLoupeSelectors, selectors[4]));
        assertTrue(containsElement(fromLoupeSelectors, selectors[6]));
        assertTrue(containsElement(fromLoupeSelectors, selectors[7]));
        assertTrue(containsElement(fromLoupeSelectors, selectors[8]));
        assertTrue(containsElement(fromLoupeSelectors, selectors[9]));

        assertFalse(containsElement(fromLoupeSelectors, ownerSel));
        assertFalse(containsElement(fromLoupeSelectors, selectors[10]));
        assertFalse(containsElement(fromLoupeSelectors, selectors[5]));
    }
}