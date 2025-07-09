// [ smart-contracts/script/InitializeTokenHelper.s.sol ]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

// Core Diamond Interfaces & Structs
import {IDiamond} from "../src/interfaces/IDiamond.sol"; // <-- FIX: Add direct import for FacetCut struct
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";

// The facet to initialize AND the facet to verify with
import {TokenHelperFacet} from "../src/facets/TokenHelper/TokenHelperFacet.sol";
import {AccessControlFacet} from "../src/facets/AccessControl/AccessControlFacet.sol";
import {TOKEN_ADMIN_ROLE} from "../src/facets/TokenHelper/ITokenHelper.sol";

/**
 * @title InitializeTokenHelper
 * @notice A dedicated script to ensure the TokenHelperFacet is initialized correctly.
 * @dev This script performs a diamondCut to call the `initializeTokenHelper` function.
 *      It should be run by the diamond's owner. It finds the deployed facet address
 *      from the diamond itself to ensure it calls the correct, active implementation.
 *
 * HOW TO RUN:
 * forge script script/InitializeTokenHelper.s.sol:InitializeTokenHelper --rpc-url arbitrum --broadcast -vvvv
 */
contract InitializeTokenHelper is Script, Test {
    function run() external {
        // --- Configuration ---
        console.log("Reading configuration from .env file...");
        address diamondAddress = vm.envAddress("DIAMOND_ADDRESS");
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address ownerAddress = vm.addr(ownerPrivateKey);

        // --- Validation ---
        require(diamondAddress != address(0), "DIAMOND_ADDRESS not set in .env");
        require(ownerPrivateKey != 0, "PRIVATE_KEY not set in .env");

        console.log("Target Diamond:", diamondAddress);
        console.log("Executing as Owner:", ownerAddress);

        // --- Prepare the Initialization Call ---
        IDiamondCut diamond = IDiamondCut(diamondAddress);
        IDiamondLoupe loupe = IDiamondLoupe(diamondAddress);

        // Find the deployed address of the TokenHelperFacet from the diamond itself
        address facetAddress = loupe.facetAddress(TokenHelperFacet.initializeTokenHelper.selector);
        require(facetAddress != address(0), "TokenHelperFacet not found on the diamond.");
        console.log("Found active TokenHelperFacet at:", facetAddress);
        
        // Prepare the calldata for the initializeTokenHelper function.
        // We will grant the admin role to the owner executing this script.
        bytes memory initCalldata = abi.encodeWithSelector(
            TokenHelperFacet.initializeTokenHelper.selector,
            ownerAddress 
        );

        // --- Execute the diamondCut ---
        console.log("Executing diamondCut to call initializeTokenHelper...");
        vm.startBroadcast(ownerPrivateKey);

        // We are not changing any facets, so the cut array is empty.
        // We are only using the `_init` and `_calldata` parameters to run our function.
        diamond.diamondCut(new IDiamond.FacetCut[](0), facetAddress, initCalldata);

        vm.stopBroadcast();

        // --- Verification ---
        console.log("Verifying initialization...");
        bool isAdmin = AccessControlFacet(diamondAddress).hasRole(TOKEN_ADMIN_ROLE, ownerAddress);
        assertTrue(isAdmin, "Verification FAILED: Owner was not granted TOKEN_ADMIN_ROLE.");

        console.log(unicode"\n✅ TokenHelperFacet successfully initialized!");
        console.log("   - Admin Role Holder:", ownerAddress);
    }
}