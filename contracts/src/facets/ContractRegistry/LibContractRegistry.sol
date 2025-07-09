// [IDEMPOTENT INITIALIZER => smart-contracts/src/facets/ContractRegistry/LibContractRegistry.sol]
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {
    ContractRegistryStorage,
    ContractInfo,
    ContractAdded,
    ContractTypeAdded,
    ContractStatusUpdated,
    ContractAlreadyAdded,
    ContractNotAdded,
    NextContractIdSet,
    NextContractIdTooLow,
    ContractNameEmpty,
    InvalidContractAddress,
    InvalidContractType,
    ContractTypeEmpty,
    ContractTypeAlreadyExists,
    ContractTypeNotFound,
    ContractNotFound,
    CR_AlreadyInitialized
} from "./IContractRegistry.sol"; // CR_RolesAlreadyConfigured removed as it's an ACL concern

library LibContractRegistry {
    bytes32 constant STORAGE_POSITION = keccak256("fraktal.mev-bot.contract-registry-storage");

    function getStorage() internal pure returns (ContractRegistryStorage storage ds) {
        bytes32 pos = STORAGE_POSITION;
        assembly {
            ds.slot := pos
        }
    }

    // MODIFIED for Idempotency
    function initialize() internal {
        ContractRegistryStorage storage ds = getStorage();
        if (ds.initialized) {
            return; // Silently return if already initialized
        }
        ds.initialized = true;
        if (ds.nextContractId == 0) {
            ds.nextContractId = 1;
        }
        if (ds.nextContractTypeId == 0) {
            ds.nextContractTypeId = 1;
        }
    }

    function addContract(string memory name, address addr, uint16 contractType) internal returns (bool success) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) revert CR_AlreadyInitialized();

        if (bytes(name).length == 0) revert ContractNameEmpty();
        if (addr == address(0)) revert InvalidContractAddress();
        if (bytes(ds.contractTypeIdsToName[contractType]).length == 0) revert InvalidContractType();

        if (ds.addedContracts[addr]) {
            revert ContractAlreadyAdded(addr);
        }

        uint256 id = ds.nextContractId;
        ds.contractIds[addr] = id;
        ds.addedContracts[addr] = true;
        ds.activeContracts[addr] = true;
        ds.contracts[id] = ContractInfo({name: name, addr: addr, contractType: contractType});

        ds.nextContractId++;
        emit ContractAdded(id, name, addr, contractType);
        return true;
    }

    function addContractType(string memory cType) internal returns (bool success) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) revert CR_AlreadyInitialized();

        if (bytes(cType).length == 0) revert ContractTypeEmpty();
        if (ds.contractTypes[cType]) revert ContractTypeAlreadyExists();

        uint16 id = ds.nextContractTypeId;
        ds.contractTypes[cType] = true;
        ds.contractTypeIds[cType] = id;
        ds.contractTypeIdsToName[id] = cType;

        ds.nextContractTypeId++;
        emit ContractTypeAdded(cType, id);
        return true;
    }

    function setNextContractId(uint256 id) internal returns (bool success) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) revert CR_AlreadyInitialized();
        uint256 currentNextId = ds.nextContractId == 0 ? 1 : ds.nextContractId;
        if (id == 0 || id <= currentNextId) {
            revert NextContractIdTooLow(currentNextId, id);
        }
        ds.nextContractId = id;
        emit NextContractIdSet(id);
        return true;
    }

    function setContractActive(address addr, bool state) internal returns (uint16 contractType) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) revert CR_AlreadyInitialized();
        if (!ds.addedContracts[addr]) {
            revert ContractNotAdded(addr);
        }
        ds.activeContracts[addr] = state;
        emit ContractStatusUpdated(addr, state);

        uint256 id = ds.contractIds[addr];
        if (ds.contracts[id].addr == address(0)) {
            revert ContractNotFound();
        }
        return ds.contracts[id].contractType;
    }

    function hasContract(address addr) internal view returns (bool) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) return false;
        return ds.addedContracts[addr];
    }

    function hasContractType(string memory cType) internal view returns (bool) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) return false;
        return ds.contractTypes[cType];
    }

    function getContractInfo(uint256 id) internal view returns (ContractInfo memory) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) revert CR_AlreadyInitialized();
        ContractInfo memory info = ds.contracts[id];
        if (info.addr == address(0)) {
            revert ContractNotFound();
        }
        return info;
    }

    function getContractByAddress(address addr) internal view returns (ContractInfo memory) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) revert CR_AlreadyInitialized();
        if (!ds.addedContracts[addr]) {
            revert ContractNotFound();
        }
        uint256 id = ds.contractIds[addr];
        ContractInfo memory info = ds.contracts[id];
        if (info.addr == address(0)) {
            revert ContractNotFound();
        }
        return info;
    }

    function getContractType(uint16 typeId) internal view returns (string memory) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) revert CR_AlreadyInitialized();
        string memory cType = ds.contractTypeIdsToName[typeId];
        if (bytes(cType).length == 0) revert ContractTypeNotFound();
        return cType;
    }

    function getNextContractId() internal view returns (uint256) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) return 1; // Default if not initialized
        uint256 nextId = ds.nextContractId;
        return nextId == 0 ? 1 : nextId;
    }

    function getNextContractTypeId() internal view returns (uint16) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) return 1; // Default if not initialized
        return ds.nextContractTypeId == 0 ? 1 : ds.nextContractTypeId;
    }

    function isContractActive(address addr) internal view returns (bool) {
        ContractRegistryStorage storage ds = getStorage();
        if (!ds.initialized) return false;
        return ds.addedContracts[addr] && ds.activeContracts[addr];
    }
}
