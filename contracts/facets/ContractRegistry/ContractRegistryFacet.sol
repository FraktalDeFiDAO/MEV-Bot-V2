// File: src/facets/ContractRegistry/ContractRegistryFacet.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    IContractRegistry,
    ContractInfo,
    CR_RolesAlreadyConfigured,
    CONTRACT_REGISTRY_ADMIN_ROLE
} // Constant inherited from IContractRegistry
from "./IContractRegistry.sol";
import {LibContractRegistry} from "./LibContractRegistry.sol";
import {LibAccessControl} from "../AccessControl/LibAccessControl.sol";
import {IAccessControl, DEFAULT_ADMIN_ROLE, Unauthorized, ZeroAddress} from "../AccessControl/IAccessControl.sol";

contract ContractRegistryFacet is IContractRegistry {
    // bytes32 public constant CONTRACT_REGISTRY_ADMIN_ROLE = keccak256("CONTRACT_REGISTRY_ADMIN_ROLE"); // Now inherited
    event ContractRegistryInitialized(address indexed initialAdmin);

    function initializeContractRegistry(address initialAdmin) external virtual override {
        LibAccessControl.enforceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        if (initialAdmin == address(0)) revert ZeroAddress();
        LibContractRegistry.initialize();

        bytes32 currentAdmin = LibAccessControl.getRoleAdmin(CONTRACT_REGISTRY_ADMIN_ROLE);
        if (currentAdmin != bytes32(0) && currentAdmin != DEFAULT_ADMIN_ROLE) {
            revert CR_RolesAlreadyConfigured();
        }

        LibAccessControl.setRoleAdmin(CONTRACT_REGISTRY_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        LibAccessControl.grantRole(CONTRACT_REGISTRY_ADMIN_ROLE, initialAdmin);
        if (msg.sender != initialAdmin && LibAccessControl.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            LibAccessControl.grantRole(CONTRACT_REGISTRY_ADMIN_ROLE, msg.sender);
        }
        emit ContractRegistryInitialized(initialAdmin);
    }

    modifier onlyContractRegistryAdmin() {
        if (
            !LibAccessControl.hasRole(CONTRACT_REGISTRY_ADMIN_ROLE, msg.sender)
                && !LibAccessControl.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) {
            revert Unauthorized(CONTRACT_REGISTRY_ADMIN_ROLE, msg.sender);
        }
        _;
    }

    function addContract(string memory name, address addr, uint16 contractType)
        external
        virtual
        override
        onlyContractRegistryAdmin
        returns (bool)
    {
        return LibContractRegistry.addContract(name, addr, contractType);
    }

    function addContractType(string memory cType) external virtual override onlyContractRegistryAdmin returns (bool) {
        return LibContractRegistry.addContractType(cType);
    }

    function setNextContractId(uint256 id) external virtual override onlyContractRegistryAdmin returns (bool) {
        return LibContractRegistry.setNextContractId(id);
    }

    function setContractActive(address addr, bool state)
        external
        virtual
        override
        onlyContractRegistryAdmin
        returns (uint16 contractType)
    {
        return LibContractRegistry.setContractActive(addr, state);
    }

    function hasContract(address addr) external view virtual override returns (bool) {
        return LibContractRegistry.hasContract(addr);
    }

    function hasContractType(string memory cType) external view virtual override returns (bool) {
        return LibContractRegistry.hasContractType(cType);
    }

    function getContractInfo(uint256 id) external view virtual override returns (ContractInfo memory) {
        return LibContractRegistry.getContractInfo(id);
    }

    function getContractByAddress(address addr) external view virtual override returns (ContractInfo memory) {
        return LibContractRegistry.getContractByAddress(addr);
    }

    function getContractType(uint16 typeId) external view virtual override returns (string memory) {
        return LibContractRegistry.getContractType(typeId);
    }

    function getNextContractId() external view virtual override returns (uint256) {
        return LibContractRegistry.getNextContractId();
    }

    function getNextContractTypeId() external view virtual override returns (uint16) {
        return LibContractRegistry.getNextContractTypeId();
    }

    function isContractActive(address addr) external view virtual override returns (bool) {
        return LibContractRegistry.isContractActive(addr);
    }
}
