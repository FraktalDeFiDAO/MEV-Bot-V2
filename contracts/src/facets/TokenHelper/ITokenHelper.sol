// File: smart-contracts/src/facets/TokenHelper/ITokenHelper.sol
// SPDX-License-Identifier: Fraktal-Protocol
pragma solidity 0.8.28;

struct TokenHelperStorage {
    mapping(address => uint16) tokenAddressToIdMap;
    mapping(uint16 => TokenInfo) tokenIdToInfoMap;
    uint16 tokensCount;
    bool initialized;
}

struct TokenInfo {
    string name;
    string symbol;
    address tokenAddress;
    uint8 decimals;
    bool isActive;
}

event TokenAdded(address indexed tokenAddress, uint16 indexed tokenId, string name, string symbol, uint8 decimals);

event TokenStatusChanged(address indexed tokenAddress, uint16 indexed tokenId, bool isActive);

// Errors
error TokenAlreadyExists(address tokenAddress);
error TokenNotFoundByAddress(address tokenAddress);
error TokenNotFoundById(uint16 tokenId);
error InvalidTokenId();
error TH_MetadataFetchFailed(address tokenAddress);
error TH_MaxTokenCapacityReached();
error TH_AlreadyInitialized();
error TH_RolesAlreadyConfigured();

// Constant defined in the interface
bytes32 constant TOKEN_ADMIN_ROLE = keccak256("TOKEN_ADMIN_ROLE");

interface ITokenHelper {
    function initializeTokenHelper(address initialAdmin) external;
    function addToken(address tokenAddress) external returns (bool);
    function hasToken(address tokenAddress) external view returns (bool);
    function setTokenActive(address tokenAddress, bool isActive) external returns (bool);
    function activateToken(address tokenAddress) external returns (bool);
    function deactivateToken(address tokenAddress) external returns (bool);
    function fetchTokenInfo(address tokenAddress) external view returns (TokenInfo memory);
    function getTokenById(uint16 id) external view returns (TokenInfo memory);
    function getTokenIdByAddress(address tokenAddress) external view returns (uint16);
}
