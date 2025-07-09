// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import both Script and Test from forge-std
import "forge-std/Script.sol";
import "forge-std/Test.sol"; // <-- ADD THIS IMPORT
import "forge-std/console.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {ArbitrageFacetV2} from "../src/facets/Arbitrage/ArbitrageFacetV2.sol";

// Inherit from both Script and Test
contract UpgradeArbitrageV2 is Script, Test { // <-- ADD , Test HERE
    function run() external {
        address diamondAddress = vm.envAddress("DIAMOND_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        require(diamondAddress != address(0), "Set DIAMOND_ADDRESS in .env file");
        require(deployerPrivateKey != 0, "Set PRIVATE_KEY in .env file");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the new facet
        console.log("Deploying new ArbitrageFacetV2...");
        ArbitrageFacetV2 newArbitrageFacet = new ArbitrageFacetV2();
        console.log("   - New Facet Deployed at:", address(newArbitrageFacet));

        // 2. Prepare the cut to add the new functions
        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = newArbitrageFacet.executePoolPairArbitrage.selector;
        selectors[1] = newArbitrageFacet.assessOpportunity.selector;

        cut[0] = IDiamond.FacetCut({
            facetAddress: address(newArbitrageFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });

        // 3. Execute the cut
        IDiamondCut diamond = IDiamondCut(diamondAddress);
        console.log("Executing diamondCut to add new arbitrage functions...");
        diamond.diamondCut(cut, address(0), "");

        vm.stopBroadcast();

        // 4. Verification
        console.log("Verifying upgrade...");
        IDiamondLoupe loupe = IDiamondLoupe(diamondAddress);
        address facetAddr = loupe.facetAddress(newArbitrageFacet.executePoolPairArbitrage.selector);
        
        // This will now work because the contract inherits from Test
        assertEq(facetAddr, address(newArbitrageFacet), "Upgrade verification failed.");

        console.log(unicode"✅ Arbitrage Facet upgraded successfully with V2 functions!");
        console.log("   - New functions now point to:", facetAddr);
    }
}