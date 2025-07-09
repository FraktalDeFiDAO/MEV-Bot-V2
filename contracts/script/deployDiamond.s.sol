// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core Diamond & Interfaces
import {Diamond, DiamondArgs} from "../src/Diamond.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";

// Initializers
import {DiamondInit} from "../src/upgradeInitializers/DiamondInit.sol";
import {DiamondMultiInit} from "../src/upgradeInitializers/DiamondMultiInit.sol";

// Facets
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {AccessControlFacet} from "../src/facets/AccessControl/AccessControlFacet.sol";
import {ContractRegistryFacet} from "../src/facets/ContractRegistry/ContractRegistryFacet.sol";
import {TokenHelperFacet} from "../src/facets/TokenHelper/TokenHelperFacet.sol";
import {ExchangeHelperFacet} from "../src/facets/ExchangeHelper/ExchangeHelperFacet.sol";
import {ArbitrageFacet} from "../src/facets/Arbitrage/ArbitrageFacet.sol";

import {HelperContract} from "../test/HelperContract.sol";

contract DeployScript is Script, HelperContract {

    function run() external {
        // --- Configuration ---
        console.log("Reading configuration from .env file...");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // FIX: The root cause of all previous errors is corrected here.
        // We use the correct cheatcode `vm.addr(privateKey)` to get the deployer's public address.
        // This ensures the account signing the transaction is the same one receiving permissions.
        address initialAdminAddress = vm.addr(deployerPrivateKey);
        
        address wethAddress = vm.envAddress("WETH_ADDRESS");
        address aavePoolProviderAddress = vm.envAddress("AAVE_POOL_PROVIDER_ADDRESS");

        // --- Validation ---
        require(deployerPrivateKey != 0, "Set PRIVATE_KEY in .env file");
        require(wethAddress != address(0), "Set WETH_ADDRESS in .env file");
        require(aavePoolProviderAddress != address(0), "Set AAVE_POOL_PROVIDER_ADDRESS in .env file");

        // Start broadcasting transactions signed by the deployer.
        vm.startBroadcast(deployerPrivateKey);

        // --- 1. Deploy ALL Facets & Initializers ---
        console.log("Deploying facets...");
        DiamondCutFacet dCutF = new DiamondCutFacet();
        DiamondLoupeFacet dLoupeF = new DiamondLoupeFacet();
        AccessControlFacet accessControlF = new AccessControlFacet();
        ContractRegistryFacet contractRegistryF = new ContractRegistryFacet();
        TokenHelperFacet tokenHelperF = new TokenHelperFacet();
        ExchangeHelperFacet exchangeHelperF = new ExchangeHelperFacet();
        ArbitrageFacet arbitrageF = new ArbitrageFacet();
        DiamondInit diamondInit = new DiamondInit();
        DiamondMultiInit diamondMultiInit = new DiamondMultiInit();
        
        // --- 2. Prepare Diamond Cut ---
        // This uses the robust, hardcoded selector generation from HelperContract.
        console.log("Preparing diamond cut...");
        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](7); 
        cut[0] = IDiamond.FacetCut(address(dCutF), IDiamond.FacetCutAction.Add, generateSelectors("DiamondCutFacet"));
        cut[1] = IDiamond.FacetCut(address(dLoupeF), IDiamond.FacetCutAction.Add, generateSelectors("DiamondLoupeFacet"));
        cut[2] = IDiamond.FacetCut(address(accessControlF), IDiamond.FacetCutAction.Add, generateSelectors("AccessControlFacet"));
        cut[3] = IDiamond.FacetCut(address(contractRegistryF), IDiamond.FacetCutAction.Add, generateSelectors("ContractRegistryFacet"));
        cut[4] = IDiamond.FacetCut(address(tokenHelperF), IDiamond.FacetCutAction.Add, generateSelectors("TokenHelperFacet"));
        cut[5] = IDiamond.FacetCut(address(exchangeHelperF), IDiamond.FacetCutAction.Add, generateSelectors("ExchangeHelperFacet"));
        cut[6] = IDiamond.FacetCut(address(arbitrageF), IDiamond.FacetCutAction.Add, generateSelectors("ArbitrageFacet"));

        // --- 3. Prepare Initialization Calls ---
        // This sequence correctly initializes the entire system in the constructor.
        address[] memory initAddresses = new address[](5);
        bytes[] memory initCalldata = new bytes[](5);

        // Call 1: Standard ERC165 setup.
        initAddresses[0] = address(diamondInit);
        initCalldata[0] = abi.encodeWithSignature("init()");

        // Call 2: Set up the Access Control system, granting the deployer the DEFAULT_ADMIN_ROLE.
        initAddresses[1] = address(accessControlF);
        initCalldata[1] = abi.encodeWithSelector(accessControlF.initializeOwner.selector, initialAdminAddress);

        // Call 3 & 4 & 5: Initialize the other facets. These calls will now succeed because the
        // `msg.sender` (the diamond) is making a delegatecall, and the ultimate caller (the deployer)
        // has been granted the necessary admin role in the step above.
        initAddresses[2] = address(contractRegistryF);
        initCalldata[2] = abi.encodeWithSelector(contractRegistryF.initializeContractRegistry.selector, initialAdminAddress);

        initAddresses[3] = address(tokenHelperF);
        initCalldata[3] = abi.encodeWithSelector(tokenHelperF.initializeTokenHelper.selector, initialAdminAddress);
        
        initAddresses[4] = address(arbitrageF);
        initCalldata[4] = abi.encodeWithSelector(arbitrageF.initialize.selector, wethAddress, aavePoolProviderAddress, initialAdminAddress);

        bytes memory multiInitCalldata = abi.encodeWithSelector(DiamondMultiInit.multiInit.selector, initAddresses, initCalldata);

        // --- 4. Deploy the Diamond ---
        console.log("Deploying Diamond...");
        DiamondArgs memory args = DiamondArgs({
            owner: initialAdminAddress, // The admin is the owner of the diamond structure itself.
            init: address(diamondMultiInit),
            initCalldata: multiInitCalldata
        });
        Diamond diamond = new Diamond(cut, args);

        // --- 5. Post-Deployment: Initialize ExchangeHelperFacet ---
        // This final initialization call is made after deployment. It succeeds because the
        // deployer, who is sending this transaction, now has the DEFAULT_ADMIN_ROLE.
        console.log("Post-deployment setup for ExchangeHelperFacet...");
        ExchangeHelperFacet(address(diamond)).initializeExchangeHelper(initialAdminAddress, initialAdminAddress, address(diamond));

        vm.stopBroadcast();

        console.log(unicode"✅ Diamond deployed successfully!");
        console.log("   - Diamond Address:", address(diamond));
        console.log("   - Owner/Admin:", initialAdminAddress);
    }
}