// [ smart-contracts/script/verify.s.sol ]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title VerifyDiamondContracts
 * @notice Verifies all contracts related to the deployed diamond on Arbiscan.
 * @dev This script must be run AFTER the diamond has been deployed.
 *      It reads the deployed addresses from your .env file and uses Forge's FFI
 *      to call `forge verify-contract` for each one.
 *
 * PRE-REQUISITES:
 * 1. Your .env file MUST be populated with the deployed addresses of your diamond
 *    and all of its facets. Example:
 *    DIAMOND_ADDRESS=0x...
 *    DIAMOND_CUT_FACET_ADDRESS=0x...
 *    DIAMOND_LOUPE_FACET_ADDRESS=0x...
 *    ACCESS_CONTROL_FACET_ADDRESS=0x...
 *    CONTRACT_REGISTRY_FACET_ADDRESS=0x...
 *    TOKEN_HELPER_FACET_ADDRESS=0x...
 *    EXCHANGE_HELPER_FACET_ADDRESS=0x...
 *    ARBITRAGE_FACET_ADDRESS=0x...
 *    ARBITRAGE_FACET_V2_ADDRESS=0x...
 *    DIAMOND_INIT_ADDRESS=0x...
 *    DIAMOND_MULTI_INIT_ADDRESS=0x...
 *
 * 2. Your .env file MUST contain ARBISCAN_API_KEY.
 *
 * 3. Your foundry.toml MUST have `ffi = true` enabled.
 *
 * HOW TO RUN:
 * forge script script/verify.s.sol:VerifyDiamondContracts --rpc-url arbitrum --broadcast -vvvv
 */
contract VerifyDiamondContracts is Script {
    string private etherscanApiKey;
    string private verifierUrl = "https://api.arbiscan.io/api";

    function run() external {
        etherscanApiKey = vm.envString("ARBISCAN_API_KEY");
        require(bytes(etherscanApiKey).length > 0, "ARBISCAN_API_KEY not found in .env");

        console.log("Beginning verification of all diamond contracts...");

        vm.startBroadcast();

        // 1. Verify the main Diamond contract (it has constructor args)
        address diamondAddress = vm.envAddress("DIAMOND_ADDRESS");
        require(diamondAddress != address(0), "DIAMOND_ADDRESS not set in .env");
        _verify("Diamond", diamondAddress, "src/Diamond.sol:Diamond");

        // 2. Verify all Facets (they have no constructor args)
        _verifyFacet("DiamondCutFacet", vm.envAddress("DIAMOND_CUT_FACET_ADDRESS"), "src/facets/DiamondCutFacet.sol:DiamondCutFacet");
        _verifyFacet("DiamondLoupeFacet", vm.envAddress("DIAMOND_LOUPE_FACET_ADDRESS"), "src/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet");
        _verifyFacet("AccessControlFacet", vm.envAddress("ACCESS_CONTROL_FACET_ADDRESS"), "src/facets/AccessControl/AccessControlFacet.sol:AccessControlFacet");
        _verifyFacet("ContractRegistryFacet", vm.envAddress("CONTRACT_REGISTRY_FACET_ADDRESS"), "src/facets/ContractRegistry/ContractRegistryFacet.sol:ContractRegistryFacet");
        _verifyFacet("TokenHelperFacet", vm.envAddress("TOKEN_HELPER_FACET_ADDRESS"), "src/facets/TokenHelper/TokenHelperFacet.sol:TokenHelperFacet");
        _verifyFacet("ExchangeHelperFacet", vm.envAddress("EXCHANGE_HELPER_FACET_ADDRESS"), "src/facets/ExchangeHelper/ExchangeHelperFacet.sol:ExchangeHelperFacet");
        _verifyFacet("ArbitrageFacet", vm.envAddress("ARBITRAGE_FACET_ADDRESS"), "src/facets/Arbitrage/ArbitrageFacet.sol:ArbitrageFacet");
        _verifyFacet("ArbitrageFacetV2", vm.envAddress("ARBITRAGE_FACET_V2_ADDRESS"), "src/facets/Arbitrage/ArbitrageFacetV2.sol:ArbitrageFacetV2");

        // 3. Verify Initializer contracts (no constructor args)
        _verify("DiamondInit", vm.envAddress("DIAMOND_INIT_ADDRESS"), "src/upgradeInitializers/DiamondInit.sol:DiamondInit");
        _verify("DiamondMultiInit", vm.envAddress("DIAMOND_MULTI_INIT_ADDRESS"), "src/upgradeInitializers/DiamondMultiInit.sol:DiamondMultiInit");
        
        vm.stopBroadcast();

        console.log(unicode"\n✅ All contracts submitted for verification.");
    }

    function _verifyFacet(string memory name, address facetAddress, string memory contractPath) private {
        // Facets have no constructor arguments, so verification is straightforward.
        _verify(name, facetAddress, contractPath);
    }
    
    function _verify(string memory name, address contractAddress, string memory contractPath) private {
        if (contractAddress == address(0)) {
            console.log(string.concat("--> Skipping verification for ", name, ": Address not found in .env"));
            return;
        }

        console.log(unicode"\nVerifying", name, "at", vm.toString(contractAddress));

        string[] memory inputs = new string[](10);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(contractAddress);
        inputs[3] = contractPath;
        inputs[4] = "--chain-id";
        inputs[5] = "42161"; // Arbitrum One Chain ID
        inputs[6] = "--verifier";
        inputs[7] = "etherscan";
        inputs[8] = "--etherscan-api-key";
        inputs[9] = etherscanApiKey;
        
        bytes memory res = vm.ffi(inputs);
        string memory output = string(res);

        // Check if the output contains "OK" or "Already Verified"
        if (bytes(output).length > 0) {
            console.log(output);
        } else {
            console.log(unicode"--> ❌ Verification failed or FFI returned empty. Check output above.");
        }
    }
}