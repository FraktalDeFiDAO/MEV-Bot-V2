// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct TokenInfo {
    address tokenAddress;
    uint8 decimals;
}

/// @dev Role constant used by the TokenHelperFacet for access control
bytes32 constant TOKEN_ADMIN_ROLE = keccak256("TOKEN_ADMIN_ROLE");

/// @dev Error thrown when attempting to add a token that already exists
error TokenAlreadyExists();
/// @dev Error thrown when a token is not found by address lookup
error TokenNotFoundByAddress();
/// @dev Error thrown when a token is not found by id lookup
error TokenNotFoundById();
/// @dev Error thrown when a zero token id/address is supplied
error InvalidTokenId();
/// @dev Error thrown when roles have already been configured
error TH_RolesAlreadyConfigured();

interface ITokenHelper {
    function initializeTokenHelper(address initialAdmin) external;

    function addToken(address tokenAddress) external returns (bool);

    function hasToken(address tokenAddress) external view returns (bool);

    function setTokenActive(address tokenAddress, bool _isActive)
        external
        returns (bool);

    function activateToken(address tokenAddress) external returns (bool);

    function deactivateToken(address tokenAddress) external returns (bool);

    function fetchTokenInfo(address tokenAddress) external view returns (TokenInfo memory);

    function getTokenById(uint16 id) external view returns (TokenInfo memory);

    function getTokenIdByAddress(address tokenAddress) external view returns (uint16);

    function getTokenInfo(address token) external view returns (TokenInfo memory);
}
