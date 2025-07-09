// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControl, DEFAULT_ADMIN_ROLE, Unauthorized} from "./IAccessControl.sol"; 
import {LibAccessControl} from "./LibAccessControl.sol"; 

contract AccessControlFacet is IAccessControl {

    /**
     * @notice Initializes the LibAccessControl storage, setting the initial owner.
     * @dev This function should be called only once, during the diamond's deployment.
     *      It sets the owner of the access control system and grants them the DEFAULT_ADMIN_ROLE.
     * @param initialOwner The address to be granted initial ownership and admin rights.
     */
    function initializeOwner(address initialOwner) external {
        // This function does not require an access control check itself, as it is
        // intended to be called from the `init` parameter of a diamond cut, which
        // is already protected by the diamond's ownership.
        LibAccessControl.initializeOwner(initialOwner);
    }

    function owner() external view override returns (address) {
        return LibAccessControl.owner();
    }

    function pendingOwner() external view override returns (address) {
        return LibAccessControl.pendingOwner();
    }

    function transferOwnership(address newOwner) external override {
        LibAccessControl.enforceOwner(msg.sender);
        LibAccessControl.transferOwnership(newOwner);
    }

    function acceptOwnership() external override {
        LibAccessControl.acceptOwnership();
    }

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        return LibAccessControl.hasRole(role, account);
    }

    function getRoleAdmin(bytes32 role) external view override returns (bytes32) {
        return LibAccessControl.getRoleAdmin(role);
    }

    function grantRole(bytes32 role, address account) external override {
        LibAccessControl.enforceRole(LibAccessControl.getRoleAdmin(role), msg.sender);
        LibAccessControl.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external override {
        LibAccessControl.enforceRole(LibAccessControl.getRoleAdmin(role), msg.sender);
        LibAccessControl.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) external override {
        LibAccessControl.renounceRole(role, account);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external override {
        LibAccessControl.enforceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        LibAccessControl.setRoleAdmin(role, adminRole);
    }

    function initializeRoles(address roleHolder, bytes32 specificAdminRole, bytes32 writerRole, bytes32 readerRole)
        external
        override
    {
        LibAccessControl.enforceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        LibAccessControl.initializeRoles(roleHolder, specificAdminRole, writerRole, readerRole);
    }
}