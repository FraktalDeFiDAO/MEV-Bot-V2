// [IDEMPOTENT INITIALIZER => smart-contracts/src/facets/AccessControl/LibAccessControl.sol ]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RoleData, AccessStorage, IAccessControl, DEFAULT_ADMIN_ROLE} from "./IAccessControl.sol";
import {
    NotOwner,
    NotPendingOwner,
    ZeroAddress,
    Unauthorized,
    RoleGranted,
    RoleRevoked,
    RoleAdminChanged,
    OwnershipTransferStarted,
    OwnershipTransferred
} from "./IAccessControl.sol";

library LibAccessControl {
    bytes32 internal constant STORAGE_SLOT = keccak256("access.control.storage.v2");

    // event DebugInitializeOwner(address dsOwnerBefore, address initOwnerParam, bool dsOwnerWasZero, address dsOwnerAfter, bool initOwnerHasDarAfter, bool libAlreadyInitialized);
    // event DebugHasRole(bytes32 role, address account, bool hasIt);

    function accessStorage() internal pure returns (AccessStorage storage ds) {
        bytes32 position = STORAGE_SLOT;
        assembly {
            ds.slot := position
        }
    }

    function enforceOwner(address account) internal view {
        if (account != accessStorage()._owner) revert NotOwner();
    }

    function enforceOwner() internal view {
        enforceOwner(msg.sender);
    }

    function enforceRole(bytes32 role, address account) internal view {
        if (!hasRole(role, account)) revert Unauthorized(role, account);
    }

    function enforceRole(bytes32 role) internal view {
        enforceRole(role, msg.sender);
    }

    function enforceRoleOrAdmin(bytes32 role, address account) internal view {
        if (!hasRole(role, account) && !hasRole(DEFAULT_ADMIN_ROLE, account)) {
            revert Unauthorized(role, account);
        }
    }

    function enforceRoleOrAdmin(bytes32 role) internal view {
        enforceRoleOrAdmin(role, msg.sender);
    }

    function hasRole(bytes32 role, address account) internal view returns (bool) {
        if (account == address(0)) return false;
        bool result = accessStorage()._roles[role].members[account];
        // emit DebugHasRole(role, account, result);
        return result;
    }

    function grantRole(bytes32 role, address account) internal {
        if (account == address(0)) revert ZeroAddress();
        AccessStorage storage ds = accessStorage();
        if (!ds._roles[role].members[account]) {
            ds._roles[role].members[account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function revokeRole(bytes32 role, address account) internal {
        if (account == address(0)) revert ZeroAddress();
        AccessStorage storage ds = accessStorage();
        if (ds._roles[role].members[account]) {
            ds._roles[role].members[account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function renounceRole(bytes32 role, address account) internal {
        if (account != msg.sender) revert Unauthorized(role, msg.sender);
        revokeRole(role, account);
    }

    function getRoleAdmin(bytes32 role) internal view returns (bytes32) {
        bytes32 adminRole = accessStorage()._roles[role].adminRole;
        return adminRole == bytes32(0) ? DEFAULT_ADMIN_ROLE : adminRole;
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        AccessStorage storage ds = accessStorage();
        bytes32 previousAdminRole = ds._roles[role].adminRole;
        bytes32 actualPreviousAdminRole = previousAdminRole == bytes32(0) ? DEFAULT_ADMIN_ROLE : previousAdminRole;

        ds._roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, actualPreviousAdminRole, adminRole);
    }

    function owner() internal view returns (address) {
        return accessStorage()._owner;
    }

    function pendingOwner() internal view returns (address) {
        return accessStorage()._pendingOwner;
    }

    function transferOwnership(address newOwner) internal {
        if (newOwner == address(0)) revert ZeroAddress();
        AccessStorage storage ds = accessStorage();
        emit OwnershipTransferStarted(ds._owner, newOwner);
        ds._pendingOwner = newOwner;
    }

    function acceptOwnership() internal {
        AccessStorage storage s = accessStorage();
        address _pendingOwner = s._pendingOwner;
        if (msg.sender != _pendingOwner) revert NotPendingOwner();
        address oldOwner = s._owner;
        s._owner = _pendingOwner;
        s._pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, s._owner);
    }

    function initializeOwner(address initOwner) internal {
        AccessStorage storage ds = accessStorage();
        // Commenting out unused debug variables to clear warnings
        // address dsOwnerBefore = ds._owner;
        // bool dsOwnerWasZero = ds._owner == address(0);
        // bool libAlreadyInitialized = ds._initialized; // For debug event

        if (ds._initialized) {
            // If this LibAccessControl system has been initialized AT ALL by ANYONE.
            // It's already initialized. The global owner is set (ds._owner).
            // If the current initOwner is that global owner, ensure they have DAR.
            if (ds._owner == initOwner) {
                if (!hasRole(DEFAULT_ADMIN_ROLE, initOwner)) {
                    grantRole(DEFAULT_ADMIN_ROLE, initOwner);
                }
            }
            // If ds._owner != initOwner (global owner is set, but to someone else),
            // then initOwner does NOT get DAR from this function. They are not the global owner.
            // emit DebugInitializeOwner(dsOwnerBefore, initOwner, dsOwnerWasZero, ds._owner, hasRole(DEFAULT_ADMIN_ROLE, initOwner), libAlreadyInitialized);
            return;
        }

        // ds._initialized is false, so this is the very first initialization.
        if (initOwner == address(0)) revert ZeroAddress();

        ds._owner = initOwner; // Set global owner
        ds._initialized = true; // Mark as initialized
        emit OwnershipTransferred(address(0), initOwner);
        grantRole(DEFAULT_ADMIN_ROLE, initOwner); // Grant DAR to the new global owner
            // emit DebugInitializeOwner(dsOwnerBefore, initOwner, dsOwnerWasZero, ds._owner, hasRole(DEFAULT_ADMIN_ROLE, initOwner), libAlreadyInitialized);
    }

    function initializeRoles(address roleHolder, bytes32 specificAdminRole, bytes32 writerRole, bytes32 readerRole)
        internal
    {
        if (roleHolder == address(0)) revert ZeroAddress();
        if (specificAdminRole == bytes32(0) || writerRole == bytes32(0) || readerRole == bytes32(0)) {
            revert("LibAccessControl: Invalid role parameter for hierarchy setup");
        }

        setRoleAdmin(specificAdminRole, DEFAULT_ADMIN_ROLE);
        setRoleAdmin(writerRole, specificAdminRole);
        setRoleAdmin(readerRole, specificAdminRole);

        grantRole(specificAdminRole, roleHolder);
        grantRole(writerRole, roleHolder);
        grantRole(readerRole, roleHolder);
    }
}
