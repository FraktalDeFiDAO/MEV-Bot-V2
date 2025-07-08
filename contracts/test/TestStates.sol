// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title TestStates
 * @author Timo Neumann <timo@fyde.fi>, Rohan Sundar <rohan@fyde.fi>
 * @notice Abstract contracts for the shared setup of the diamond tests.
 * @dev This file has been corrected to use explicit variable names (`diamondCutFacet` instead of `dCutF`)
 *      to resolve a compiler error related to an undeclared identifier, which was likely caused
 *      by a name collision.
 */
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

/**
 * @notice Base state for all diamond tests. Deploys a diamond with the essential facets.
 */
abstract contract StateDeployDiamond is HelperContract {
    Diamond diamond;
    // FIX: Renamed variables to be more explicit and avoid potential compiler name collisions.
    DiamondCutFacet diamondCutFacet;
    DiamondLoupeFacet diamondLoupeFacet;
    AccessControlFacet accessControlFacet;
    DiamondInit diamondInit;

    IDiamondLoupe ILoupe;
    IDiamondCut ICut;

    string[] facetNames;
    address[] facetAddressList;

    function setUp() public virtual {
        // --- 1. Deploy all necessary facet contracts ---
        diamondCutFacet = new DiamondCutFacet();
        diamondLoupeFacet = new DiamondLoupeFacet();
        accessControlFacet = new AccessControlFacet();
        diamondInit = new DiamondInit();
        facetNames = ["DiamondCutFacet", "DiamondLoupeFacet", "AccessControlFacet"];

        // --- 2. Prepare the initial set of facet cuts for the diamond constructor ---
        FacetCut[] memory cut = new FacetCut[](3);
        cut[0] = FacetCut(address(diamondCutFacet), IDiamond.FacetCutAction.Add, generateSelectors("DiamondCutFacet"));
        cut[1] = FacetCut(address(diamondLoupeFacet), IDiamond.FacetCutAction.Add, generateSelectors("DiamondLoupeFacet"));
        cut[2] = FacetCut(address(accessControlFacet), IDiamond.FacetCutAction.Add, generateSelectors("AccessControlFacet"));

        // --- 3. Prepare the initialization call ---
        bytes[] memory initCalls = new bytes[](2);
        initCalls[0] = abi.encodeWithSignature("init()");
        initCalls[1] = abi.encodeWithSelector(AccessControlFacet.initializeOwner.selector, address(this));
        
        DiamondMultiInit multiInit = new DiamondMultiInit();
        address[] memory initAddresses = new address[](2);
        initAddresses[0] = address(diamondInit);
        initAddresses[1] = address(accessControlFacet);
        bytes memory multiInitCalldata = abi.encodeWithSelector(multiInit.multiInit.selector, initAddresses, initCalls);

        // --- 4. Deploy the Diamond ---
        DiamondArgs memory _args = DiamondArgs({
            owner: address(this), 
            init: address(multiInit), 
            initCalldata: multiInitCalldata
        });
        diamond = new Diamond(cut, _args);

        // --- 5. Set up interfaces for interacting with the newly created diamond ---
        ILoupe = IDiamondLoupe(address(diamond));
        ICut = IDiamondCut(address(diamond));

        facetAddressList = ILoupe.facetAddresses();
    }
}

/**
 * @notice State for testing the addition of a new facet (`Test1Facet`).
 */
abstract contract StateAddFacet1 is StateDeployDiamond {
    Test1Facet test1Facet;

    function setUp() public virtual override {
        super.setUp();
        test1Facet = new Test1Facet();
        
        bytes4[] memory selectors = generateSelectors("Test1Facet");
        bytes4[] memory fromGenSelectors = removeElement(bytes4(keccak256("supportsInterface(bytes4)")), selectors);

        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(test1Facet),
            action: FacetCutAction.Add,
            functionSelectors: fromGenSelectors
        });
        ICut.diamondCut(facetCut, address(0x0), "");
    }
}

/**
 * @notice State for testing the addition of a second new facet (`Test2Facet`).
 */
abstract contract StateAddFacet2 is StateAddFacet1 {
    Test2Facet test2Facet;

    function setUp() public virtual override {
        super.setUp();
        test2Facet = new Test2Facet();
        bytes4[] memory fromGenSelectors = generateSelectors("Test2Facet");

        FacetCut[] memory facetCut = new FacetCut[](1);
        facetCut[0] = FacetCut({
            facetAddress: address(test2Facet),
            action: FacetCutAction.Add,
            functionSelectors: fromGenSelectors
        });
        ICut.diamondCut(facetCut, address(0x0), "");
    }
}

/**
 * @notice State for testing a specific diamond storage cache bug.
 */
abstract contract StateCacheBug is StateDeployDiamond {
    Test1Facet test1Facet;
    bytes4 ownerSel = 0x8da5cb5b; // owner()
    bytes4[] selectors;

    function setUp() public virtual override {
        super.setUp();
        test1Facet = new Test1Facet();

        selectors = new bytes4[](11);
        selectors[0] = 0x19e3b533; // test1Func2()
        selectors[1] = 0x0716c2ae; // test1Func3()
        selectors[2] = 0x11046047; // test1Func4()
        selectors[3] = 0xcf3bbe18; // test1Func5()
        selectors[4] = 0x24c1d5a7; // test1Func6()
        selectors[5] = 0xcbb835f6; // test1Func7()
        selectors[6] = 0x0165a18b; // test1Func8()
        selectors[7] = 0x697d8193; // test1Func9()
        selectors[8] = 0x88340479; // test1Func10()
        selectors[9] = 0x29713551; // test1Func11()
        selectors[10] = 0xcd4a6f98; // test1Func12()

        FacetCut[] memory cut = new FacetCut[](1);
        cut[0] = FacetCut({facetAddress: address(test1Facet), action: FacetCutAction.Add, functionSelectors: selectors});
        ICut.diamondCut(cut, address(0x0), "");

        bytes4[] memory newSelectors = new bytes4[](3);
        newSelectors[0] = ownerSel;
        newSelectors[1] = selectors[5]; // test1Func7
        newSelectors[2] = selectors[10]; // test1Func12

        cut[0] = FacetCut({facetAddress: address(0x0), action: FacetCutAction.Remove, functionSelectors: newSelectors});
        ICut.diamondCut(cut, address(0x0), "");
    }
}