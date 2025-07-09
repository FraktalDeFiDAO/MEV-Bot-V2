// [IDEMPOTENT INITIALIZER => smart-contracts/src/facets/ExchangeHelper/LibExchangeHelperStorage.sol]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    IExchangeHelper,
    ExchangeHelperStorage,
    Exchange,
    ExchangePlatform,
    ExchangeCategory,
    ExchangeAdded,
    ExchangeStatusChanged,
    EH_ExchangeNotFoundById,
    EH_ExchangeAlreadyExists,
    EH_ExchangeIdTaken,
    EH_InvalidNameLength,
    EH_InvalidFactoryContract,
    EH_NotInitialized,
    EH_AlreadyInitialized,
    EH_InvalidAddress,
    EH_MaxExchangesReached
} from "./IExchangeHelper.sol";
import {IContractRegistry, ContractInfo} from "../ContractRegistry/IContractRegistry.sol"; // ContractNotFound not used directly here

library LibExchangeHelperStorage {
    bytes32 constant STORAGE_POSITION = keccak256("fraktal.protocol.exchangehelper.storage");

    function layout() internal pure returns (ExchangeHelperStorage storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // MODIFIED for Idempotency
    function initialize(address _owner, address _registryAddress) internal {
        ExchangeHelperStorage storage ds = layout();
        if (ds.initialized) {
            // Optionally, verify if params are consistent if re-initializing for test reset
            // if (ds.owner != _owner || ds.registry != _registryAddress) {
            //     revert("LibExchangeHelperStorage: Inconsistent re-initialization attempt");
            // }
            return; // Silently return if already initialized
        }
        if (_owner == address(0) || _registryAddress == address(0)) revert EH_InvalidAddress();

        ds.owner = _owner;
        ds.registry = _registryAddress;
        ds.initialized = true;
        ds.VERSION = "1.0.5"; // Version bump for idempotency change
    }

    function addExchange(
        string memory _name,
        uint256 _factoryId, // Changed from uint to uint256 to match struct
        ExchangePlatform _platform,
        ExchangeCategory _category,
        bool _acceptsNativeETH,
        address _platformTokenAddress
    ) internal returns (uint16 exchangeId) {
        ExchangeHelperStorage storage ds = layout();
        if (!ds.initialized) revert EH_NotInitialized();
        if (_factoryId == 0) revert EH_InvalidFactoryContract();
        if (bytes(_name).length == 0 || bytes(_name).length > 32) revert EH_InvalidNameLength();

        // Max check is for type(uint16).max, but name check implies existence
        if (
            ds.exchangesInfo[_name].id != 0
                || (ds.exchangesInfo[_name].id == 0 && bytes(ds.exchangesInfo[_name].name).length > 0)
        ) {
            revert EH_ExchangeAlreadyExists(_name);
        }

        exchangeId = ds.exchangeCount;
        if (exchangeId == type(uint16).max) revert EH_MaxExchangesReached();

        // Check if ID is already taken by a different name (should not happen if count is managed correctly)
        if (bytes(ds.exchangeIdToNameMap[exchangeId]).length != 0) revert EH_ExchangeIdTaken(exchangeId);

        ds.exchangeIdToNameMap[exchangeId] = _name;
        ds.exchangesInfo[_name] = Exchange({
            id: exchangeId,
            factoryId: _factoryId,
            name: _name,
            isActive: true,
            platform: _platform,
            category: _category,
            acceptsNativeETH: _acceptsNativeETH,
            platformTokenAddress: _platformTokenAddress
        });
        ds.exchangeCount++;

        emit ExchangeAdded(
            exchangeId, _name, _factoryId, _platform, _category, _acceptsNativeETH, _platformTokenAddress
        );
        return exchangeId;
    }

    function setExchangeActive(uint16 _exchangeId, bool _isActive) internal returns (bool) {
        ExchangeHelperStorage storage ds = layout();
        if (!ds.initialized) revert EH_NotInitialized();
        if (_exchangeId >= ds.exchangeCount) revert EH_ExchangeNotFoundById(_exchangeId);

        string memory name = ds.exchangeIdToNameMap[_exchangeId];
        if (bytes(name).length == 0) revert EH_ExchangeNotFoundById(_exchangeId); // Should be redundant if _exchangeId < ds.exchangeCount

        Exchange storage ex = ds.exchangesInfo[name];
        if (ex.id != _exchangeId) revert EH_ExchangeNotFoundById(_exchangeId); // Sanity check
        if (ex.isActive == _isActive) return true;

        ex.isActive = _isActive;
        emit ExchangeStatusChanged(_exchangeId, name, _isActive);
        return true;
    }

    function hasExchange(string memory _name) internal view returns (bool) {
        ExchangeHelperStorage storage ds = layout();
        if (!ds.initialized) return false;

        Exchange memory ex = ds.exchangesInfo[_name];
        // Check if id is non-default (0 for first added, or if using type(uint16).max for uninit)
        // A more robust check is if name mapping exists and that exchange is active
        return bytes(ex.name).length > 0 && ex.isActive;
    }

    function getExchangeById(uint16 id) internal view returns (Exchange memory) {
        ExchangeHelperStorage storage ds = layout();
        if (!ds.initialized) revert EH_NotInitialized();
        if (id >= ds.exchangeCount) revert EH_ExchangeNotFoundById(id);

        string memory name = ds.exchangeIdToNameMap[id];
        if (bytes(name).length == 0) revert EH_ExchangeNotFoundById(id);

        Exchange memory ex = ds.exchangesInfo[name];
        if (!ex.isActive) revert EH_ExchangeNotFoundById(id); // Or specific "ExchangeInactive"

        return ex;
    }

    function getExchangeByIdAndFactory(uint16 id, uint256 factoryId) internal view returns (Exchange memory) {
        ExchangeHelperStorage storage ds = layout();
        if (!ds.initialized) revert EH_NotInitialized();

        Exchange memory ex = getExchangeById(id); // Relies on getExchangeById for active and existence checks

        if (ex.factoryId == factoryId) {
            return ex;
        }
        // If factoryId doesn't match, it's effectively not found for this specific query
        revert EH_ExchangeNotFoundById(id);
    }

    function hasExchangeContract(address _contractAddress) internal view returns (bool) {
        ExchangeHelperStorage storage ds = layout();
        if (!ds.initialized || ds.registry == address(0)) return false;
        return IContractRegistry(ds.registry).hasContract(_contractAddress);
    }

    function getExchangeContractByAddress(address _contractAddress) internal view returns (ContractInfo memory) {
        ExchangeHelperStorage storage ds = layout();
        if (!ds.initialized || ds.registry == address(0)) revert EH_InvalidAddress(); // Or specific error
        return IContractRegistry(ds.registry).getContractByAddress(_contractAddress);
    }
}
