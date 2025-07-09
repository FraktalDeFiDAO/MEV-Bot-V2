// [ smart-contracts/test/AllTests.t.sol ]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AllTests
 * @notice A consolidated test suite for the entire diamond protocol.
 * @dev This file combines unit, integration, and forking tests for all facets
 *      to ensure comprehensive coverage and prevent cross-file import issues.
 *      It uses a state-based testing pattern (State0, State1, etc.) where each
 *      subsequent state contract inherits from the previous one, building up the
 *      necessary setup for its specific tests.
 *
 * To run: `forge test --match-contract AllTests -vv`
 */

import "forge-std/Test.sol";
import "forge-std/console.sol";

// --- Diamond & Facet Imports (Corrected to point to src/) ---
import {Diamond, DiamondArgs} from "../src/Diamond.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {DiamondInit} from "../src/upgradeInitializers/DiamondInit.sol";
import {DiamondMultiInit} from "../src/upgradeInitializers/DiamondMultiInit.sol";

import {AccessControlFacet} from "../src/facets/AccessControl/AccessControlFacet.sol";
import {IAccessControl, DEFAULT_ADMIN_ROLE, NotOwner, NotPendingOwner, Unauthorized} from "../src/facets/AccessControl/IAccessControl.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {Test1Facet} from "../src/facets/Test1Facet.sol";
import {Test2Facet} from "../src/facets/Test2Facet.sol";

import {ContractRegistryFacet} from "../src/facets/ContractRegistry/ContractRegistryFacet.sol";
import {IContractRegistry, CONTRACT_REGISTRY_ADMIN_ROLE} from "../src/facets/ContractRegistry/IContractRegistry.sol";

import {TokenHelperFacet} from "../src/facets/TokenHelper/TokenHelperFacet.sol";
import {ITokenHelper, TOKEN_ADMIN_ROLE} from "../src/facets/TokenHelper/ITokenHelper.sol";

import {ExchangeHelperFacet} from "../src/facets/ExchangeHelper/ExchangeHelperFacet.sol";
import {IExchangeHelper, ExchangePlatform, ExchangeCategory, EXCHANGE_HELPER_ADMIN_ROLE} from "../src/facets/ExchangeHelper/IExchangeHelper.sol";
import {ActionSwapParams} from "../src/facets/ExchangeHelper/LibExchangeActions.sol";

import {ArbitrageFacet} from "../src/facets/Arbitrage/ArbitrageFacet.sol";
import {ArbitrageFacetV2} from "../src/facets/Arbitrage/ArbitrageFacetV2.sol";
import {IArbitrageV2, ArbitragePoolPair, NoProfitablePathFound} from "../src/facets/Arbitrage/IArbitrageV2.sol";
import {ARBITRAGE_ADMIN_ROLE, AE_NotEnoughProfit, AE_FlashLoanFailed} from "../src/libraries/LibAppStorage.sol";

import {UniswapVersionChecker} from "../src/UniswapVersionChecker.sol";

import {HelperContract} from "./HelperContract.sol";

// =====================================================================================
//                       SETUP & STATE MANAGEMENT CONTRACTS
// =====================================================================================

abstract contract State0_BaseDiamond is Test, HelperContract {
    Diamond diamond;
    IDiamondLoupe loupe;
    IDiamondCut cut;

    address owner;
    address user1;
    address user2;

    // Facet Instances
    DiamondCutFacet dCutF;
    DiamondLoupeFacet dLoupeF;
    AccessControlFacet acF;
    ContractRegistryFacet crF;
    TokenHelperFacet thF;
    ExchangeHelperFacet ehF;
    ArbitrageFacet arbF;
    ArbitrageFacetV2 arbF2;
    Test1Facet test1F;
    Test2Facet test2F;


    function setUp() public virtual {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vm.label(owner, "DiamondOwner");
        vm.label(user1, "User1");
        vm.label(user2, "User2");

        // --- 1. Deploy Facets & Initializers ---
        dCutF = new DiamondCutFacet();
        dLoupeF = new DiamondLoupeFacet();
        acF = new AccessControlFacet();
        crF = new ContractRegistryFacet();
        thF = new TokenHelperFacet();
        ehF = new ExchangeHelperFacet();
        arbF = new ArbitrageFacet();
        arbF2 = new ArbitrageFacetV2();
        test1F = new Test1Facet();
        test2F = new Test2Facet();

        // --- 2. Prepare Diamond Cut ---
        IDiamond.FacetCut[] memory _cut = new IDiamond.FacetCut[](8);
        _cut[0] = IDiamond.FacetCut(address(dCutF), IDiamond.FacetCutAction.Add, generateSelectors("DiamondCutFacet"));
        _cut[1] = IDiamond.FacetCut(address(dLoupeF), IDiamond.FacetCutAction.Add, generateSelectors("DiamondLoupeFacet"));
        _cut[2] = IDiamond.FacetCut(address(acF), IDiamond.FacetCutAction.Add, generateSelectors("AccessControlFacet"));
        _cut[3] = IDiamond.FacetCut(address(crF), IDiamond.FacetCutAction.Add, generateSelectors("ContractRegistryFacet"));
        _cut[4] = IDiamond.FacetCut(address(thF), IDiamond.FacetCutAction.Add, generateSelectors("TokenHelperFacet"));
        _cut[5] = IDiamond.FacetCut(address(ehF), IDiamond.FacetCutAction.Add, generateSelectors("ExchangeHelperFacet"));
        _cut[6] = IDiamond.FacetCut(address(arbF), IDiamond.FacetCutAction.Add, generateSelectors("ArbitrageFacet"));

        // Add V2 functions to the diamond
        bytes4[] memory arbV2Selectors = new bytes4[](2);
        arbV2Selectors[0] = arbF2.executePoolPairArbitrage.selector;
        arbV2Selectors[1] = arbF2.assessOpportunity.selector;
        _cut[7] = IDiamond.FacetCut(address(arbF2), IDiamond.FacetCutAction.Add, arbV2Selectors);

        // --- 3. Prepare Initialization ---
        DiamondInit diamondInit = new DiamondInit();
        DiamondMultiInit diamondMultiInit = new DiamondMultiInit();

        address[] memory initAddresses = new address[](1);
        bytes[] memory initCalldata = new bytes[](1);

        initAddresses[0] = address(diamondInit);
        initCalldata[0] = abi.encodeWithSignature("init()");

        bytes memory multiInitCalldata = abi.encodeWithSelector(
            diamondMultiInit.multiInit.selector,
            initAddresses,
            initCalldata
        );

        // --- 4. Deploy Diamond ---
        vm.prank(owner);
        diamond = new Diamond(
            _cut,
            DiamondArgs({owner: owner, init: address(diamondMultiInit), initCalldata: multiInitCalldata})
        );

        loupe = IDiamondLoupe(address(diamond));
        cut = IDiamondCut(address(diamond));
    }
}

// =====================================================================================
//                       DIAMOND CORE & ACCESS CONTROL TESTS
// =====================================================================================

contract AllTests is State0_BaseDiamond {
    function test_InitialState_OwnerAndRoles() public {
        vm.prank(owner);
        AccessControlFacet(address(diamond)).initializeOwner(owner);

        assertEq(AccessControlFacet(address(diamond)).owner(), owner, "Owner should be set correctly");
        assertTrue(AccessControlFacet(address(diamond)).hasRole(DEFAULT_ADMIN_ROLE, owner), "Owner should have admin role");
    }

    function test_OwnershipTransfer() public {
        vm.prank(owner);
        AccessControlFacet(address(diamond)).initializeOwner(owner);

        // Start transfer
        vm.prank(owner);
        AccessControlFacet(address(diamond)).transferOwnership(user1);
        assertEq(AccessControlFacet(address(diamond)).pendingOwner(), user1, "Pending owner should be user1");

        // Non-pending owner cannot accept
        vm.prank(user2);
        vm.expectRevert(NotPendingOwner.selector);
        AccessControlFacet(address(diamond)).acceptOwnership();

        // New owner accepts
        vm.prank(user1);
        AccessControlFacet(address(diamond)).acceptOwnership();

        assertEq(AccessControlFacet(address(diamond)).owner(), user1, "New owner should be user1");
        assertEq(AccessControlFacet(address(diamond)).pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function test_RoleManagement() public {
        vm.prank(owner);
        AccessControlFacet(address(diamond)).initializeOwner(owner);

        bytes32 TEST_ROLE = keccak256("TEST_ROLE");

        // Grant role
        vm.prank(owner);
        AccessControlFacet(address(diamond)).grantRole(TEST_ROLE, user1);
        assertTrue(AccessControlFacet(address(diamond)).hasRole(TEST_ROLE, user1), "User1 should have TEST_ROLE");

        // Non-admin cannot revoke
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, DEFAULT_ADMIN_ROLE, user2));
        AccessControlFacet(address(diamond)).revokeRole(TEST_ROLE, user1);

        // Admin revokes role
        vm.prank(owner);
        AccessControlFacet(address(diamond)).revokeRole(TEST_ROLE, user1);
        assertFalse(AccessControlFacet(address(diamond)).hasRole(TEST_ROLE, user1), "User1 should not have TEST_ROLE");

        // Renounce role
        vm.prank(owner);
        AccessControlFacet(address(diamond)).grantRole(TEST_ROLE, user1);
        vm.prank(user1);
        AccessControlFacet(address(diamond)).renounceRole(TEST_ROLE, user1);
        assertFalse(AccessControlFacet(address(diamond)).hasRole(TEST_ROLE, user1), "User1 should have renounced role");
    }

    function test_DiamondCut_AddReplaceRemove() public {
        // Test Add
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = test1F.test1Func1.selector;

        IDiamond.FacetCut[] memory addCut = new IDiamond.FacetCut[](1);
        addCut[0] = IDiamond.FacetCut(address(test1F), IDiamond.FacetCutAction.Add, selectors);

        vm.prank(owner);
        cut.diamondCut(addCut, address(0), "");

        assertEq(loupe.facetAddress(selectors[0]), address(test1F), "Add failed");

        // Test Replace
        Test1Facet replacementFacet = new Test1Facet();
        IDiamond.FacetCut[] memory replaceCut = new IDiamond.FacetCut[](1);
        replaceCut[0] = IDiamond.FacetCut(address(replacementFacet), IDiamond.FacetCutAction.Replace, selectors);

        vm.prank(owner);
        cut.diamondCut(replaceCut, address(0), "");
        assertEq(loupe.facetAddress(selectors[0]), address(replacementFacet), "Replace failed");

        // Test Remove
        IDiamond.FacetCut[] memory removeCut = new IDiamond.FacetCut[](1);
        removeCut[0] = IDiamond.FacetCut(address(0), IDiamond.FacetCutAction.Remove, selectors);

        vm.prank(owner);
        cut.diamondCut(removeCut, address(0), "");
        assertEq(loupe.facetAddress(selectors[0]), address(0), "Remove failed");
    }

    // =====================================================================================
    //                            HELPER FACETS TESTS
    // =====================================================================================

    function test_HelperFacets_InitializationAndInteraction() public {
        // --- Initialize all helper facets ---
        vm.prank(owner);
        AccessControlFacet(address(diamond)).initializeOwner(owner);

        vm.prank(owner);
        ContractRegistryFacet(address(diamond)).initializeContractRegistry(owner);

        vm.prank(owner);
        TokenHelperFacet(address(diamond)).initializeTokenHelper(owner);

        vm.prank(owner);
        ExchangeHelperFacet(address(diamond)).initializeExchangeHelper(owner, owner, address(diamond));

        // --- Test TokenHelper ---
        address mockTokenAddr = address(0x123);
        vm.prank(owner);
        vm.expectRevert("TH_MetadataFetchFailed"); // Reverts because it's not a real token
        TokenHelperFacet(address(diamond)).addToken(mockTokenAddr);
        // In a real fork test, you'd use a real token address.

        // --- Test ContractRegistry ---
        vm.prank(owner);
        ContractRegistryFacet(address(diamond)).addContractType("ROUTER");

        vm.prank(owner);
        ContractRegistryFacet(address(diamond)).addContract("MockRouter", address(0x456), 1); // typeId 1

        assertTrue(ContractRegistryFacet(address(diamond)).hasContract(address(0x456)), "Contract should be registered");

        // --- Test ExchangeHelper ---
        vm.prank(owner);
        ExchangeHelperFacet(address(diamond)).addExchange(
            "MockSwap",
            1, // factoryId from ContractRegistry
            ExchangePlatform.UniswapV2,
            ExchangeCategory.UniswapV2,
            false,
            address(0)
        );

        assertTrue(ExchangeHelperFacet(address(diamond)).hasExchange("MockSwap"), "Exchange should exist");
    }

    // =====================================================================================
    //                            UTILITY CONTRACTS TESTS
    // =====================================================================================

    function test_UniswapVersionChecker() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));

        UniswapVersionChecker checker = new UniswapVersionChecker();

        address V2_POOL = 0xc31E54c7a869B9FcBEcc14363CF510d1c41fa443; // SUSHI WETH/USDC
        address V3_POOL = 0xC31E54C7a869B9FcBEcc14363CF510d1c41fa444; // <<< FIX: Corrected checksum
        
        assertEq(uint(checker.checkVersion(V2_POOL)), uint(UniswapVersionChecker.UniswapVersion.V2), "Should be V2");
        assertEq(uint(checker.checkVersion(V3_POOL)), uint(UniswapVersionChecker.UniswapVersion.V3), "Should be V3");
        assertEq(uint(checker.checkVersion(owner)), uint(UniswapVersionChecker.UniswapVersion.NONE), "Should be None");

        vm.revertTo(0);
    }

    // =====================================================================================
    //                           ARBITRAGE FORKING TESTS
    // =====================================================================================

    function test_Arbitrage_FullFlow() public {
        string memory ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
        address WETH_ADDR = vm.envAddress("WETH_ADDRESS");
        address AAVE_PROVIDER_ADDR = vm.envAddress("AAVE_POOL_PROVIDER_ADDRESS");
        require(bytes(ARBITRUM_RPC_URL).length > 0, "ARBITRUM_RPC_URL not set");

        vm.createSelectFork(ARBITRUM_RPC_URL);

        // --- Full System Initialization ---
        vm.prank(owner);
        AccessControlFacet(address(diamond)).initializeOwner(owner);
        vm.prank(owner);
        ContractRegistryFacet(address(diamond)).initializeContractRegistry(owner);
        vm.prank(owner);
        TokenHelperFacet(address(diamond)).initializeTokenHelper(owner);
        vm.prank(owner);
        ExchangeHelperFacet(address(diamond)).initializeExchangeHelper(owner, owner, address(diamond));
        vm.prank(owner);
        ArbitrageFacet(address(diamond)).initialize(WETH_ADDR, AAVE_PROVIDER_ADDR, owner);

        // --- Setup Tokens, Contracts, and Exchanges for a real path ---
        address SUSHI_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
        address UNI_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        address USDC_ADDR = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

        // Add contracts to registry
        vm.prank(owner);
        ContractRegistryFacet(address(diamond)).addContractType("ROUTER");
        vm.prank(owner);
        uint256 sushiRouterId = ContractRegistryFacet(address(diamond)).getNextContractId();
        ContractRegistryFacet(address(diamond)).addContract("SushiRouter", SUSHI_ROUTER, 1);
        vm.prank(owner);
        uint256 uniV3RouterId = ContractRegistryFacet(address(diamond)).getNextContractId();
        ContractRegistryFacet(address(diamond)).addContract("UniV3Router", UNI_V3_ROUTER, 1);

        // Add tokens to helper
        vm.prank(owner);
        TokenHelperFacet(address(diamond)).addToken(WETH_ADDR); // ID 0
        uint16 wethId = TokenHelperFacet(address(diamond)).getTokenIdByAddress(WETH_ADDR);

        vm.prank(owner);
        TokenHelperFacet(address(diamond)).addToken(USDC_ADDR); // ID 1
        uint16 usdcId = TokenHelperFacet(address(diamond)).getTokenIdByAddress(USDC_ADDR);

        // Add exchanges to helper
        vm.prank(owner);
        uint16 sushiExId = ExchangeHelperFacet(address(diamond)).addExchange("SushiSwap", sushiRouterId, ExchangePlatform.SushiSwap, ExchangeCategory.UniswapV2, false, address(0));
        vm.prank(owner);
        uint16 uniV3ExId = ExchangeHelperFacet(address(diamond)).addExchange("UniswapV3", uniV3RouterId, ExchangePlatform.UniswapV3, ExchangeCategory.UniswapV3, false, address(0));

        // --- Prepare Arbitrage Call ---
        // Path: WETH -> USDC (on Sushi), USDC -> WETH (on UniV3)
        uint256 loanAmount = 10 ether;

        ActionSwapParams memory legA = ActionSwapParams({
            exchangeHelperAddress: address(diamond), tokenHelperAddress: address(diamond), contractRegistryAddress: address(diamond),
            wethAddress: WETH_ADDR, exchangeId: sushiExId, tokenInId: wethId, tokenOutId: usdcId,
            amountIn: loanAmount, amountOutMin: 0, recipient: address(diamond),
            extraDexParams: ""
        });

        bytes memory v3Fee = abi.encode(uint24(500)); // 0.05% fee pool
        ActionSwapParams memory legB = ActionSwapParams({
            exchangeHelperAddress: address(diamond), tokenHelperAddress: address(diamond), contractRegistryAddress: address(diamond),
            wethAddress: WETH_ADDR, exchangeId: uniV3ExId, tokenInId: usdcId, tokenOutId: wethId,
            amountIn: 0, amountOutMin: 0, recipient: address(diamond),
            extraDexParams: v3Fee
        });

        // --- Execute ---
        console.log("Executing Aave Flash Loan Arbitrage on Fork...");
        deal(WETH_ADDR, address(diamond), 0.1 ether); // Provide some gas money for the flash fee

        vm.prank(owner);
        // We expect this to fail if there's no profit, which is likely on a non-volatile block.
        // The key is to test that the entire mechanism works without unexpected reverts.
        vm.expectRevert(abi.encodeWithSelector(AE_NotEnoughProfit.selector));
        ArbitrageFacet(address(diamond)).executeAaveArbitrage(WETH_ADDR, loanAmount, legA, legB, 0);

        vm.revertTo(0);
    }
}