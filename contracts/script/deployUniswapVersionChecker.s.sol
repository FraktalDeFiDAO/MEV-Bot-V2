// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/UniswapVersionChecker.sol";

/**
 * @title DeployUniswapVersionChecker
 * @notice A dedicated script to deploy the UniswapVersionChecker contract.
 * @dev This contract is crucial for the off-chain bot to correctly identify
 *      the protocol version of a given liquidity pool.
 */
contract DeployUniswapVersionChecker is Script {

    function run() external {
        // --- Configuration ---
        console.log("Reading deployer private key from .env file...");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Ensure the private key is set in the environment.
        require(deployerPrivateKey != 0, "Error: PRIVATE_KEY not found in .env file.");

        // --- Deployment ---
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying UniswapVersionChecker...");
        UniswapVersionChecker checker = new UniswapVersionChecker();

        vm.stopBroadcast();

        // --- Success Logging ---
        console.log(unicode"\n✅ UniswapVersionChecker deployed successfully!");
        console.log("   - Contract Address:", address(checker));
        console.log(unicode"   - ❗ IMPORTANT: Update this address in your Go application config (bot/App/App.go) to complete the fix.");
    }
}