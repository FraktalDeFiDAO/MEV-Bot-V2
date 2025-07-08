// File: smart-contracts/src/facets/ContractRegistry/IContractRegistry.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct ContractInfo {
    string name;
    address addr;
    uint16 contractType;
}

struct ContractRegistryStorage {
    mapping(address => uint256) contractIds;
    mapping(uint256 => ContractInfo) contracts;
    mapping(address => bool) addedContracts;
    mapping(address => bool) activeContracts;
    uint256 nextContractId;
    mapping(string => bool) contractTypes;
    mapping(string => uint16) contractTypeIds;
    mapping(uint16 => string) contractTypeIdsToName;
    uint16 nextContractTypeId;
    bool initialized;
}

// Errors
error ContractNameEmpty();
error InvalidContractAddress();
error InvalidContractType();
error ContractTypeEmpty();
error ContractTypeAlreadyExists();
error ContractTypeNotFound();
error ContractNotFound();
error NextContractIdTooLow(uint256 currentNextId, uint256 newId);
error ContractAlreadyAdded(address addr);
error ContractNotAdded(address addr);
error CR_AlreadyInitialized();
error CR_RolesAlreadyConfigured();

// Events
event NextContractIdSet(uint256 id);

event ContractAdded(uint256 id, string name, address addr, uint16 contractType);

event ContractTypeAdded(string cType, uint16 id);

event ContractStatusUpdated(address addr, bool state);

// Constant defined in the interface
bytes32 constant CONTRACT_REGISTRY_ADMIN_ROLE = keccak256("CONTRACT_REGISTRY_ADMIN_ROLE");

interface IContractRegistry {
    function initializeContractRegistry(address initialAdmin) external;
    function addContract(string memory name, address addr, uint16 contractType) external returns (bool success);
    function addContractType(string memory cType) external returns (bool success);
    function setNextContractId(uint256 id) external returns (bool success);
    function setContractActive(address addr, bool state) external returns (uint16 contractType);
    function hasContract(address addr) external view returns (bool hasC);
    function hasContractType(string memory cType) external view returns (bool hasT);
    function getContractInfo(uint256 id) external view returns (ContractInfo memory);
    function getContractByAddress(address addr) external view returns (ContractInfo memory);
    function getContractType(uint16 id) external view returns (string memory);
    function getNextContractId() external view returns (uint256);
    function getNextContractTypeId() external view returns (uint16);
    function isContractActive(address addr) external view returns (bool);
}
