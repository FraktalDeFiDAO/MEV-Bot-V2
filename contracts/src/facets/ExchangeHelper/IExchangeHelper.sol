// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum ExchangePlatform {
    Unknown,
    UniswapV2,
    UniswapV3
}

enum ExchangeCategory {
    Unknown,
    UniswapV2,
    UniswapV3
}

struct Exchange {
    uint16 id;
    uint256 factoryId;
    ExchangePlatform platform;
    ExchangeCategory category;
    bool acceptsNativeETH;
    address platformTokenAddress;
    bool isActive;
    string name;
}

struct ExchangeHelperStorage {
    address registry;
    mapping(string => Exchange) exchangesInfo;
    mapping(uint16 => string) exchangeIdToNameMap;
    uint16 nextId;
    bool initialized;
}

event ExchangeAdded(uint16 indexed id, string name);
event ExchangeStatusChanged(uint16 indexed id, bool isActive);

error EH_ExchangeNotFoundById();
error EH_ExchangeAlreadyExists();
error EH_ExchangeIdTaken();
error EH_InvalidNameLength();
error EH_InvalidFactoryContract();
error EH_NotInitialized();
error EH_AlreadyInitialized();
error EH_InvalidAddress();
error EH_MaxExchangesReached();

interface IExchangeHelper {
    function detectExchangeType(address pool) external view returns (ExchangeCategory category, bool success);
}
