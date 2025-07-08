// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core Diamond Interfaces
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";

// Facet to be upgraded
// NOTE: We deploy a new instance of this contract to get the updated bytecode.
import {ExchangeHelperFacet} from "../src/facets/ExchangeHelper/ExchangeHelperFacet.sol";

// Helper contract for generating function selectors
import {HelperContract} from "../test/HelperContract.sol";

contract UpgradeDiamond is Script, HelperContract {
    function run() external {
        // --- Configuration ---
        console.log("Reading configuration from .env file...");
        
        // The address of the Diamond to upgrade.
        // Set this in your .env file, e.g., DIAMOND_ADDRESS=0x...
        address diamondAddress = vm.envAddress("DIAMOND_ADDRESS");
        
        // The private key of the Diamond's owner.
        // Set this in your .env file, e.g., PRIVATE_KEY=...
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // --- Validation ---
        require(diamondAddress != address(0), "Set DIAMOND_ADDRESS in .env file");
        require(deployerPrivateKey != 0, "Set PRIVATE_KEY in .env file");

        // Start broadcasting transactions signed by the deployer (Diamond Owner).
        vm.startBroadcast(deployerPrivateKey);

        // --- 1. Deploy the new Facet implementation ---
        // This deploys a new contract containing the updated logic.
        console.log("Deploying new ExchangeHelperFacet implementation...");
        ExchangeHelperFacet newExchangeHelperFacet = new ExchangeHelperFacet();
        console.log("   - New ExchangeHelperFacet deployed at:", address(newExchangeHelperFacet));

        // --- 2. Prepare the Diamond Cut ---
        // We will replace all functions of the ExchangeHelperFacet with the new implementation.
        console.log("Preparing diamond cut to replace ExchangeHelperFacet...");
        
        // Get all function selectors for the facet using the helper.
        bytes4[] memory selectorsToReplace = generateSelectors("ExchangeHelperFacet");

        // Create the FacetCut struct array.
        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](1);
        cut[0] = IDiamond.FacetCut({
            facetAddress: address(newExchangeHelperFacet),
            action: IDiamond.FacetCutAction.Replace, // We are replacing the existing functions.
            functionSelectors: selectorsToReplace
        });

        // --- 3. Execute the Diamond Upgrade ---
        // We get an interface to the deployed diamond and call diamondCut.
        IDiamondCut diamond = IDiamondCut(diamondAddress);
        
        console.log("Executing diamondCut on diamond at:", diamondAddress);
        // We don't need an initialization function for this simple replacement.
        diamond.diamondCut(cut, address(0), "");

        // --- 4. Stop Broadcasting ---
        vm.stopBroadcast();

        // --- 5. Verification (Optional but Recommended) ---
        console.log("Verifying upgrade...");
        IDiamondLoupe loupe = IDiamondLoupe(diamondAddress);
        
        // Check if one of the selectors now points to the new facet address.
        bytes4 aSelector = selectorsToReplace[0];
        address newAddress = loupe.facetAddress(aSelector);
        
        assertEq(newAddress, address(newExchangeHelperFacet), "Upgrade verification failed: Selector does not point to the new facet address.");
        
        console.log(unicode"✅ Diamond upgraded successfully!");
        console.log("   - ExchangeHelperFacet selectors now point to:", newAddress);
    }
}
