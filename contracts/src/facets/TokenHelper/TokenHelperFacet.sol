// File: src/facets/TokenHelper/TokenHelperFacet.sol
// SPDX-License-Identifier: Fraktal-Protocol
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    ITokenHelper,
    TOKEN_ADMIN_ROLE,
    TokenInfo,
    TokenAlreadyExists,
    TokenNotFoundByAddress,
    TokenNotFoundById,
    InvalidTokenId,
    TH_RolesAlreadyConfigured
} from "./ITokenHelper.sol";
import {LibTokenHelper} from "./LibTokenHelper.sol";
import {LibAccessControl} from "../AccessControl/LibAccessControl.sol";
import {IAccessControl, DEFAULT_ADMIN_ROLE, Unauthorized, ZeroAddress} from "../AccessControl/IAccessControl.sol";

contract TokenHelperFacet is ITokenHelper, ReentrancyGuard {
    // bytes32 public constant TOKEN_ADMIN_ROLE = keccak256("TOKEN_ADMIN_ROLE"); // Now inherited

    function initializeTokenHelper(address initialAdmin) external virtual override {
        LibAccessControl.enforceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        if (initialAdmin == address(0)) revert ZeroAddress();
        LibTokenHelper.initialize();

        bytes32 currentAdmin = LibAccessControl.getRoleAdmin(TOKEN_ADMIN_ROLE);
        if (currentAdmin != bytes32(0) && currentAdmin != DEFAULT_ADMIN_ROLE) {
            revert TH_RolesAlreadyConfigured();
        }

        LibAccessControl.setRoleAdmin(TOKEN_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        LibAccessControl.grantRole(TOKEN_ADMIN_ROLE, initialAdmin);
        if (msg.sender != initialAdmin && LibAccessControl.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            LibAccessControl.grantRole(TOKEN_ADMIN_ROLE, msg.sender);
        }
    }

    modifier onlyTokenAdmin() {
        if (
            !LibAccessControl.hasRole(TOKEN_ADMIN_ROLE, msg.sender)
                && !LibAccessControl.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) {
            revert Unauthorized(TOKEN_ADMIN_ROLE, msg.sender);
        }
        _;
    }

    function addToken(address tokenAddress) external virtual override onlyTokenAdmin nonReentrant returns (bool) {
        return LibTokenHelper.addToken(tokenAddress);
    }

    function hasToken(address tokenAddress) external view virtual override returns (bool) {
        return LibTokenHelper.hasToken(tokenAddress);
    }

    function setTokenActive(address tokenAddress, bool _isActive)
        external
        virtual
        override
        onlyTokenAdmin
        nonReentrant
        returns (bool)
    {
        if (tokenAddress == address(0)) revert InvalidTokenId();
        return LibTokenHelper.setTokenActive(tokenAddress, _isActive);
    }

    function activateToken(address tokenAddress) external virtual override onlyTokenAdmin nonReentrant returns (bool) {
        if (tokenAddress == address(0)) revert InvalidTokenId();
        return LibTokenHelper.activateToken(tokenAddress);
    }

    function deactivateToken(address tokenAddress)
        external
        virtual
        override
        onlyTokenAdmin
        nonReentrant
        returns (bool)
    {
        if (tokenAddress == address(0)) revert InvalidTokenId();
        return LibTokenHelper.deactivateToken(tokenAddress);
    }

    // ---------------------------------------------------------------------
    // View functions
    // ---------------------------------------------------------------------

    function getTokenInfo(address token) external view override returns (TokenInfo memory) {
        return LibTokenHelper.getTokenInfo(token);
    }

    function fetchTokenInfo(address tokenAddress) external view virtual override returns (TokenInfo memory) {
        return LibTokenHelper.fetchTokenInfo(tokenAddress);
    }

    function getTokenById(uint16 id) external view virtual override returns (TokenInfo memory) {
        return LibTokenHelper.getTokenById(id);
    }

    function getTokenIdByAddress(address tokenAddress) external view virtual override returns (uint16) {
        return LibTokenHelper.getTokenIdByAddress(tokenAddress);
    }
}
