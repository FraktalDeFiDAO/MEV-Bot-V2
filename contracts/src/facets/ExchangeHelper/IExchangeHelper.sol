// File: smart-contracts/src/facets/ExchangeHelper/IExchangeHelper.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ContractInfo} from "../ContractRegistry/IContractRegistry.sol";

enum ExchangePlatform {
    Unknown,
    UniswapV2,
    UniswapV3,
    SushiSwap,
    CurvePlainPool,
    BalancerV2Vault,
    AaveV2LendingPool,
    AlgebraV19,
    AlgebraV19Differential,
    SolidlyV2,
    SolidlyV3,
    KyberSwapElastic
}

enum ExchangeCategory {
    Unknown,
    UniswapV2,
    UniswapV3,
    AlgebraV19,
    AlgebraV19Differential,
    SolidlyV2,
    SolidlyV3,
    BalancerV2,
    KyberSwapElastic,
    CurveStableSwap
}

struct ExchangeHelperStorage {
    string VERSION;
    address owner;
    bool initialized;
    address registry;
    mapping(string => Exchange) exchangesInfo;
    mapping(uint16 => string) exchangeIdToNameMap;
    uint16 exchangeCount;
}

struct Exchange {
    uint16 id;
    uint256 factoryId;
    string name;
    bool isActive;
    ExchangePlatform platform;
    ExchangeCategory category;
    bool acceptsNativeETH;
    address platformTokenAddress;
}

struct PoolParams {
    uint256 factoryId;
    uint256 token0Id;
    uint256 token1Id;
    uint24 fee;
    bytes32 poolId;
}

// Errors
error EH_InvalidExchangeType();
error EH_InvalidAddress();
error EH_InvalidTokenAddress();
error EH_InvalidFactoryAddress();
error EH_ExchangeNotFoundById(uint16 exchangeId);
error EH_ExchangeNotFoundByName(string name);
error EH_ExchangeAlreadyExists(string name);
error EH_ExchangeIdTaken(uint16 exchangeId);
error EH_InvalidNameLength();
error EH_InvalidFactoryContract();
error EH_NotInitialized();
error EH_AlreadyInitialized();
error EH_Unauthorized();
error EH_InvalidRouterContractId(uint256 routerContractId);
error EH_MaxExchangesReached();
error EH_RolesAlreadyConfigured();
error EH_ContractRegistryAddressNotSet();

// Events
event ExchangeAdded(
    uint16 indexed exchangeId,
    string name,
    uint256 factoryId,
    ExchangePlatform platform,
    ExchangeCategory category,
    bool acceptsNativeETH,
    address platformTokenAddress
);

event ExchangeStatusChanged(uint16 indexed exchangeId, string name, bool isActive);

event ExchangeContractAdded(address indexed contractAddress, string name, uint16 contractRegistryType);

event ExchangeContractStatusChanged(address indexed contractAddress, uint16 contractRegistryType, bool isActive);

event ExchangeHelperStorageOwnershipTransferred(address indexed oldOwner, address indexed newOwner);

// Constant defined in the interface
bytes32 constant EXCHANGE_HELPER_ADMIN_ROLE = keccak256("EXCHANGE_HELPER_ADMIN_ROLE");

interface IExchangeHelper {
    function initializeExchangeHelper(
        address _facetStorageOwner,
        address _initialAdmin,
        address _contractRegistryAddress
    ) external;
    function addExchange(
        string memory _name,
        uint256 _factoryId,
        ExchangePlatform _platform,
        ExchangeCategory _category,
        bool _acceptsNativeETH,
        address _platformTokenAddress
    ) external returns (uint16);
    function setExchangeActive(uint16 _exchangeId, bool _isActive) external returns (bool);
    function hasExchange(string memory _name) external view returns (bool);
    function getExchangeById(uint16 id) external view returns (Exchange memory);
    function getExchangeByIdAndFactory(uint16 id, uint256 factoryId) external view returns (Exchange memory);
    function addExchangeContract(address _contractAddress, string memory _name, uint16 _contractTypeId)
        external
        returns (bool);
    function setExchangeContractActive(address _contractAddress, bool _isActive) external returns (bool);

    function getExchangeHelperStorageOwner() external view returns (address); // Renamed
    function transferExchangeHelperStorageOwnership(address newOwner) external returns (bool); // Renamed

    function detectExchangeType(address addr) external view returns (ExchangeCategory, bool);
    function isExchangeType(address addr, ExchangeCategory expectedType) external view returns (bool);
    function getPoolOrPairAddress(PoolParams memory params) external view returns (address);
}
