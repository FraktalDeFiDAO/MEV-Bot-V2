// File: smart-contracts/src/facets/AccessControl/IAccessControl.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct AccessStorage {
    address _owner;
    address _pendingOwner;
    mapping(bytes32 => RoleData) _roles;
    bool _initialized;
}

struct RoleData {
    mapping(address => bool) members;
    bytes32 adminRole;
}

error NotOwner();
error NotPendingOwner();
error ZeroAddress();
error Unauthorized(bytes32 role, address account);
// Context-specific "RolesAlreadyConfigured" errors are in their respective I<FacetName>.sol files

event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

interface IAccessControl {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address account) external;
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
    function initializeRoles(address admin, bytes32 adminRole, bytes32 writerRole, bytes32 readerRole) external;
}
