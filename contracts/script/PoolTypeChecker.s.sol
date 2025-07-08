// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {PoolTypeChecker} from "../src/PoolTypeChecker.sol";

/**
 * @title DeployPoolTypeChecker
 * @notice A Forge script to deploy the PoolTypeChecker contract.
 * @dev This script handles the deployment transaction. The deployer's private key
 *      and the target network's RPC URL should be provided via command-line flags
 *      or environment variables.
 */
contract DeployPoolTypeChecker is Script {
    /**
     * @notice The main entry point for the deployment script.
     * @return The deployed PoolTypeChecker contract instance.
     */
    function run() public returns (PoolTypeChecker) {
        // Retrieve the deployer's private key from the environment for broadcasting.
        // This is more secure than hardcoding it in the script.
        // The `forge script` command will use this private key to sign the transaction.
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract. Since the constructor has no arguments,
        // it's a simple `new` call.
        PoolTypeChecker poolTypeChecker = new PoolTypeChecker();

        // Stop broadcasting to send the transaction.
        vm.stopBroadcast();

        // Log the address of the newly deployed contract for convenience.
        console.log("PoolTypeChecker deployed at:", address(poolTypeChecker));

        return poolTypeChecker;
    }
}