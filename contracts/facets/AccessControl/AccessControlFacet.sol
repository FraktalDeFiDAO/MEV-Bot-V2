// [CORRECTED - Global LibAccessControl Usage => smart-contracts/src/facets/AccessControl/AccessControlFacet.sol ]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControl, DEFAULT_ADMIN_ROLE, Unauthorized} from "./IAccessControl.sol"; // AccessStorage not needed here by the facet itself
import {LibAccessControl} from "./LibAccessControl.sol"; // This LibAccessControl uses its own global storage

// This facet provides an IAccessControl interface.
// It relies on LibAccessControl using its own global storage slot.
// It is NOT inherited by ArbitrageExecutioner in the current setup (AE uses Ownable + direct LibAccessControl).
// If AE were to implement IAccessControl, it *could* inherit this.
contract AccessControlFacet is
    IAccessControl // Not abstract if it implements all of IAccessControl
{
    // REMOVED: function _getAccessControlStorage() internal virtual view returns (AccessStorage storage);
    // LibAccessControl is global, no specific storage instance is passed from here.

    function owner() external view override returns (address) {
        return LibAccessControl.owner(); // Calls global LibAccessControl
    }

    function pendingOwner() external view override returns (address) {
        return LibAccessControl.pendingOwner(); // Calls global LibAccessControl
    }

    function transferOwnership(address newOwner) external override {
        // This would be guarded by LibAccessControl.enforceOwner() which checks the *global* owner.
        LibAccessControl.enforceOwner(msg.sender);
        LibAccessControl.transferOwnership(newOwner);
    }

    function acceptOwnership() external override {
        // LibAccessControl.acceptOwnership() internally checks msg.sender against global pendingOwner
        LibAccessControl.acceptOwnership();
    }

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        return LibAccessControl.hasRole(role, account); // Calls global LibAccessControl
    }

    function getRoleAdmin(bytes32 role) external view override returns (bytes32) {
        return LibAccessControl.getRoleAdmin(role); // Calls global LibAccessControl
    }

    function grantRole(bytes32 role, address account) external override {
        // Caller must have the admin role for the 'role' being granted, in the global LibAccessControl
        LibAccessControl.enforceRole(LibAccessControl.getRoleAdmin(role), msg.sender);
        LibAccessControl.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external override {
        // Caller must have the admin role for the 'role' being revoked, in the global LibAccessControl
        LibAccessControl.enforceRole(LibAccessControl.getRoleAdmin(role), msg.sender);
        LibAccessControl.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) external override {
        // LibAccessControl.renounceRole internally checks account == msg.sender
        LibAccessControl.renounceRole(role, account);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external override {
        // Only global DEFAULT_ADMIN_ROLE can change role admins
        LibAccessControl.enforceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        LibAccessControl.setRoleAdmin(role, adminRole);
    }

    function initializeRoles(address roleHolder, bytes32 specificAdminRole, bytes32 writerRole, bytes32 readerRole)
        external
        override
    {
        // Only global DEFAULT_ADMIN_ROLE can initialize roles like this
        LibAccessControl.enforceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        LibAccessControl.initializeRoles(roleHolder, specificAdminRole, writerRole, readerRole);
    }
}
