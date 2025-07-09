// [ smart-contracts/script/03-upgradeAndInitializeArbitrage.s.sol ]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core Diamond Interfaces
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";

// Facets involved in the upgrade
import {ArbitrageFacet} from "../src/facets/Arbitrage/ArbitrageFacet.sol"; // The NEW version with roles
import {AccessControlFacet} from "../src/facets/AccessControl/AccessControlFacet.sol";

// Helper for selectors
import {HelperContract} from "../test/HelperContract.sol";

// Role constant
import {ARBITRAGE_ADMIN_ROLE} from "../src/libraries/LibAppStorage.sol";

/**
 * @title UpgradeAndInitializeArbitrage
 * @notice This script upgrades the ArbitrageFacet to a new version that includes
 *         proper role-based access control and initializes this new system.
 * @dev This is necessary if the diamond was deployed with an older version of the
 *      ArbitrageFacet that lacked an initializer for its specific roles. The script
 *      performs a diamondCut to REPLACE the old facet's functions and simultaneously
 *      calls the new `initialize` function to set up the ARBITRAGE_ADMIN_ROLE.
 */
contract UpgradeAndInitializeArbitrage is Script, HelperContract {
    function run() external {
        // --- Configuration ---
        console.log("Reading configuration from .env file...");
        address diamondAddress = vm.envAddress("DIAMOND_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // These are required for the new ArbitrageFacet's initialize function
        address wethAddress = vm.envAddress("WETH_ADDRESS");
        address aavePoolProviderAddress = vm.envAddress("AAVE_POOL_PROVIDER_ADDRESS");

        // --- Validation ---
        require(diamondAddress != address(0), "DIAMOND_ADDRESS not set in .env");
        require(deployerPrivateKey != 0, "PRIVATE_KEY not set in .env");
        require(wethAddress != address(0), "WETH_ADDRESS not set in .env");
        require(aavePoolProviderAddress != address(0), "AAVE_POOL_PROVIDER_ADDRESS not set in .env");

        // The deployer (owner of the diamond) will become the arbitrage admin.
        address arbitrageAdmin = vm.addr(deployerPrivateKey);

        // --- Execution ---
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the new, corrected ArbitrageFacet implementation.
        console.log("Deploying new ArbitrageFacet implementation...");
        ArbitrageFacet newArbitrageFacet = new ArbitrageFacet();
        console.log("   - New ArbitrageFacet deployed at:", address(newArbitrageFacet));

        // 2. Prepare the `diamondCut` parameters.
        // We are REPLACING all functions of the old ArbitrageFacet.
        // The `generateSelectors` helper provides the list of function selectors to replace.
        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](1);
        cut[0] = IDiamond.FacetCut({
            facetAddress: address(newArbitrageFacet),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: generateSelectors("ArbitrageFacet")
        });

        // 3. Prepare the initialization call (`_init` and `_calldata`).
        // This call will be executed via DELEGATECALL within the diamond's context
        // as part of the `diamondCut` transaction.
        console.log("Preparing initialization call for the new facet...");
        
        // The address of the contract to call the initializer on is the new facet.
        address initAddress = address(newArbitrageFacet);
        
        // The calldata for the call is the encoded `initialize` function signature and its arguments.
        // This sets up the app storage (WETH, Aave) and configures the ARBITRAGE_ADMIN_ROLE.
        bytes memory initCalldata = abi.encodeWithSelector(
            newArbitrageFacet.initialize.selector,
            wethAddress,
            aavePoolProviderAddress,
            arbitrageAdmin
        );

        // 4. Execute the upgrade and initialization in a single atomic transaction.
        console.log("Executing diamondCut to upgrade and initialize the ArbitrageFacet...");
        IDiamondCut(diamondAddress).diamondCut(cut, initAddress, initCalldata);

        vm.stopBroadcast();

        // --- Verification ---
        console.log("Verifying upgrade and initialization...");
        
        // Check 1: Verify that the facet address for a key function has been updated.
        IDiamondLoupe loupe = IDiamondLoupe(diamondAddress);
        bytes4 aSelector = newArbitrageFacet.executeAaveArbitrage.selector;
        address currentFacetAddress = loupe.facetAddress(aSelector);
        
        assertEq(currentFacetAddress, address(newArbitrageFacet), "Verification Failed: Facet address was not updated.");
        console.log(unicode"✅ Facet address successfully updated to:", currentFacetAddress);

        // Check 2: Verify that the new role has been granted to the admin.
        AccessControlFacet accessControl = AccessControlFacet(diamondAddress);
        bool hasRole = accessControl.hasRole(ARBITRAGE_ADMIN_ROLE, arbitrageAdmin);
        
        assertTrue(hasRole, "Verification Failed: ARBITRAGE_ADMIN_ROLE was not granted.");
        console.log(unicode"✅ ARBITRAGE_ADMIN_ROLE successfully granted to:", arbitrageAdmin);
        
        console.log(unicode"\n🎉 Diamond upgrade and initialization complete!");
    }
}