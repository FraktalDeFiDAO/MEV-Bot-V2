// [ smart-contracts/script/VerifyDiamond.s.sol ]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/StdJson.sol";

// Import necessary interfaces/structs for argument reconstruction
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {DiamondArgs} from "../src/Diamond.sol";
import {HelperContract} from "../test/HelperContract.sol";

/**
 * @title VerifyDiamond
 * @notice Verifies all contracts from a deployment by reading the broadcast artifacts.
 * @dev This is the robust, correct method. It deserializes the transaction list from
 *      the `run-latest.json` file and iterates through it, reconstructing constructor
 *      arguments for the main Diamond contract to ensure a perfect match.
 *
 * HOW TO RUN:
 * 1. Ensure `ffi = true` and `fs_permissions` are set in foundry.toml.
 * 2. Ensure `ARBISCAN_API_KEY` is in your .env file.
 * 3. Run: forge script script/VerifyDiamond.s.sol:VerifyDiamond --rpc-url arbitrum -vvvv
 */
contract VerifyDiamond is Script, HelperContract {
    using stdJson for string;

    // A struct that mirrors the structure of a transaction object in run-latest.json
    struct Transaction {
        string transactionType;
        string contractName;
        address contractAddress;
        bytes arguments; // Raw constructor arguments
    }

    string private constant DEPLOY_SCRIPT_PATH = "deployDiamond.s.sol";

    function run() external {
        string memory etherscanApiKey = vm.envString("ARBISCAN_API_KEY");
        require(bytes(etherscanApiKey).length > 0, "ARBISCAN_API_KEY not found in .env");

        string memory runFilePath = _findLatestRunFile();
        console.log("Reading deployment data from:", runFilePath);
        string memory runJson = vm.readFile(runFilePath);

        Transaction[] memory txs = abi.decode(runJson.readBytes(".transactions"), (Transaction[]));

        console.log(unicode"--- Verifying All Deployed Contracts ---");

        // Loop through all deployed contracts and verify them
        for (uint i = 0; i < txs.length; i++) {
            Transaction memory currentTx = txs[i];

            if (keccak256(bytes(currentTx.transactionType)) != keccak256(bytes("CREATE"))) {
                continue;
            }

            string memory contractPath = _getContractPath(currentTx.contractName);
            if (bytes(contractPath).length == 0) {
                console.log(unicode"--> 🟡 Skipping unknown contract:", currentTx.contractName);
                continue;
            }

            if (keccak256(bytes(currentTx.contractName)) == keccak256(bytes("Diamond"))) {
                _verifyDiamond(currentTx, contractPath, runJson, etherscanApiKey);
            } else {
                _verifyContract(currentTx, contractPath, etherscanApiKey);
            }
        }
        
        console.log(unicode"\n✅ All contracts have been submitted for verification.");
    }

    function _findLatestRunFile() private returns (string memory) {
        string memory chainId = vm.toString(block.chainid);
        string memory broadcastPath = string.concat("broadcast/", DEPLOY_SCRIPT_PATH, "/", chainId, "/");
        return string.concat(broadcastPath, "run-latest.json");
    }

    function _verifyDiamond(Transaction memory diamondTx, string memory contractPath, string memory runJson, string memory etherscanApiKey) private {
        console.log(unicode"\nVerifying Diamond at", diamondTx.contractAddress, "...");
        
        bytes memory constructorArgs = _reconstructDiamondConstructorArgs(runJson);
        string memory tempPath = "temp-diamond-args.tmp";
        vm.writeFile(tempPath, vm.toString(constructorArgs));
        
        string[] memory inputs = new string[](10);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(diamondTx.contractAddress);
        inputs[3] = contractPath;
        inputs[4] = "--chain-id";
        inputs[5] = vm.toString(block.chainid);
        inputs[6] = "--etherscan-api-key";
        inputs[7] = etherscanApiKey;
        inputs[8] = "--constructor-args-path";
        inputs[9] = tempPath;

        _executeVerification(inputs);
        
        string[] memory rmInputs = new string[](2);
        rmInputs[0] = "rm";
        rmInputs[1] = tempPath;
        vm.ffi(rmInputs);
    }

    function _verifyContract(Transaction memory tx, string memory contractPath, string memory apiKey) private {
        console.log(unicode"\nVerifying", tx.contractName, tx.contractAddress, "...");
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(tx.contractAddress);
        inputs[3] = contractPath;
        inputs[4] = "--chain-id";
        inputs[5] = vm.toString(block.chainid);
        inputs[6] = "--etherscan-api-key";
        inputs[7] = apiKey;
        _executeVerification(inputs);
    }
    
    function _reconstructDiamondConstructorArgs(string memory runJson) private returns (bytes memory) {
        address dCutF_addr = _getAddressFromArtifact(runJson, "DiamondCutFacet");
        address dLoupeF_addr = _getAddressFromArtifact(runJson, "DiamondLoupeFacet");
        address acF_addr = _getAddressFromArtifact(runJson, "AccessControlFacet");
        address crF_addr = _getAddressFromArtifact(runJson, "ContractRegistryFacet");
        address thF_addr = _getAddressFromArtifact(runJson, "TokenHelperFacet");
        address ehF_addr = _getAddressFromArtifact(runJson, "ExchangeHelperFacet");
        address arbF_addr = _getAddressFromArtifact(runJson, "ArbitrageFacet");
        
        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](7);
        cut[0] = IDiamond.FacetCut(dCutF_addr, IDiamond.FacetCutAction.Add, generateSelectors("DiamondCutFacet"));
        cut[1] = IDiamond.FacetCut(dLoupeF_addr, IDiamond.FacetCutAction.Add, generateSelectors("DiamondLoupeFacet"));
        cut[2] = IDiamond.FacetCut(acF_addr, IDiamond.FacetCutAction.Add, generateSelectors("AccessControlFacet"));
        cut[3] = IDiamond.FacetCut(crF_addr, IDiamond.FacetCutAction.Add, generateSelectors("ContractRegistryFacet"));
        cut[4] = IDiamond.FacetCut(thF_addr, IDiamond.FacetCutAction.Add, generateSelectors("TokenHelperFacet"));
        cut[5] = IDiamond.FacetCut(ehF_addr, IDiamond.FacetCutAction.Add, generateSelectors("ExchangeHelperFacet"));
        cut[6] = IDiamond.FacetCut(arbF_addr, IDiamond.FacetCutAction.Add, generateSelectors("ArbitrageFacet"));
        
        string memory diamondTxQuery = ".transactions[] | select(.contractName == \"Diamond\")";
        address deployer = vm.parseAddress(runJson.readString(string.concat(diamondTxQuery, " | .from")));
        address init_addr = _getAddressFromArtifact(runJson, "DiamondMultiInit");
        
        bytes memory initCalldata = runJson.readBytes(".transactions[] | select(.contractName == \"DiamondMultiInit\") | .arguments[0]");
        
        DiamondArgs memory args = DiamondArgs({
            owner: deployer,
            init: init_addr,
            initCalldata: initCalldata
        });

        return abi.encode(cut, args);
    }
    
    function _getAddressFromArtifact(string memory runJson, string memory contractName) private returns (address) {
        string memory query = string.concat(".transactions[] | select(.contractName==\"", contractName, "\" and .transactionType==\"CREATE\") | .contractAddress");
        return vm.parseAddress(runJson.readString(query));
    }

    function _executeVerification(string[] memory inputs) private {
        bytes memory res = vm.ffi(inputs);
        string memory output = string(res);
        console.log(output);
    }

    function _getContractPath(string memory _contractName) private pure returns (string memory) {
        bytes32 nameHash = keccak256(bytes(_contractName));
        if (nameHash == keccak256(bytes("Diamond"))) return "src/Diamond.sol:Diamond";
        if (nameHash == keccak256(bytes("DiamondCutFacet"))) return "src/facets/DiamondCutFacet.sol:DiamondCutFacet";
        if (nameHash == keccak256(bytes("DiamondLoupeFacet"))) return "src/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet";
        if (nameHash == keccak256(bytes("AccessControlFacet"))) return "src/facets/AccessControl/AccessControlFacet.sol:AccessControlFacet";
        if (nameHash == keccak256(bytes("ContractRegistryFacet"))) return "src/facets/ContractRegistry/ContractRegistryFacet.sol:ContractRegistryFacet";
        if (nameHash == keccak256(bytes("TokenHelperFacet"))) return "src/facets/TokenHelper/TokenHelperFacet.sol:TokenHelperFacet";
        if (nameHash == keccak256(bytes("ExchangeHelperFacet"))) return "src/facets/ExchangeHelper/ExchangeHelperFacet.sol:ExchangeHelperFacet";
        if (nameHash == keccak256(bytes("ArbitrageFacet"))) return "src/facets/Arbitrage/ArbitrageFacet.sol:ArbitrageFacet";
        if (nameHash == keccak256(bytes("ArbitrageFacetV2"))) return "src/facets/Arbitrage/ArbitrageFacetV2.sol:ArbitrageFacetV2";
        if (nameHash == keccak256(bytes("DiamondInit"))) return "src/upgradeInitializers/DiamondInit.sol:DiamondInit";
        if (nameHash == keccak256(bytes("DiamondMultiInit"))) return "src/upgradeInitializers/DiamondMultiInit.sol:DiamondMultiInit";
        return "";
    }
}