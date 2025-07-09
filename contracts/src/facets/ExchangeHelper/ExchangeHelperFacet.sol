// File: src/facets/ExchangeHelper/ExchangeHelperFacet.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/OpenZeppelin/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {
    IExchangeHelper,
    Exchange,
    ExchangePlatform,
    ExchangeCategory,
    PoolParams,
    EH_Unauthorized,
    EH_InvalidAddress,
    EH_MaxExchangesReached,
    ExchangeContractAdded,
    ExchangeContractStatusChanged,
    EH_ContractRegistryAddressNotSet,
    EH_RolesAlreadyConfigured,
    ExchangeHelperStorageOwnershipTransferred,
    EXCHANGE_HELPER_ADMIN_ROLE
} // Constant inherited from IExchangeHelper
from "./IExchangeHelper.sol";
import {LibExchangeHelperStorage} from "./LibExchangeHelperStorage.sol";
import {LibExchangeUtils} from "./LibExchangeUtils.sol";
import {LibAccessControl} from "../AccessControl/LibAccessControl.sol";
import {IAccessControl, DEFAULT_ADMIN_ROLE} from "../AccessControl/IAccessControl.sol";
import {IContractRegistry} from "../ContractRegistry/IContractRegistry.sol";

contract ExchangeHelperFacet is IExchangeHelper, ReentrancyGuard {
    // bytes32 public constant EXCHANGE_HELPER_ADMIN_ROLE = keccak256("EXCHANGE_HELPER_ADMIN_ROLE"); // Now inherited

    modifier onlyExchangeAdmin() {
        if (
            !LibAccessControl.hasRole(EXCHANGE_HELPER_ADMIN_ROLE, msg.sender)
                && !LibAccessControl.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) {
            revert EH_Unauthorized();
        }
        _;
    }

    function initializeExchangeHelper(
        address _facetStorageOwner,
        address _initialAdmin,
        address _contractRegistryAddress
    ) external virtual override {
        LibAccessControl.enforceRole(DEFAULT_ADMIN_ROLE, msg.sender);

        if (_facetStorageOwner == address(0) || _initialAdmin == address(0) || _contractRegistryAddress == address(0)) {
            revert EH_InvalidAddress();
        }
        LibExchangeHelperStorage.initialize(_facetStorageOwner, _contractRegistryAddress);

        bytes32 currentAdmin = LibAccessControl.getRoleAdmin(EXCHANGE_HELPER_ADMIN_ROLE);
        if (currentAdmin != bytes32(0) && currentAdmin != DEFAULT_ADMIN_ROLE) {
            revert EH_RolesAlreadyConfigured();
        }

        LibAccessControl.setRoleAdmin(EXCHANGE_HELPER_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        LibAccessControl.grantRole(EXCHANGE_HELPER_ADMIN_ROLE, _initialAdmin);
        if (msg.sender != _initialAdmin && LibAccessControl.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            LibAccessControl.grantRole(EXCHANGE_HELPER_ADMIN_ROLE, msg.sender);
        }
    }

    function getExchangeHelperStorageOwner() external view virtual override returns (address) {
        return LibExchangeHelperStorage.layout().owner;
    }

    function transferExchangeHelperStorageOwnership(address newOwner)
        external
        virtual
        override
        nonReentrant
        returns (bool)
    {
        address currentStorageOwner = LibExchangeHelperStorage.layout().owner;
        if (msg.sender != currentStorageOwner && !LibAccessControl.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert EH_Unauthorized();
        }
        if (newOwner == address(0)) revert EH_InvalidAddress();
        LibExchangeHelperStorage.layout().owner = newOwner;
        emit ExchangeHelperStorageOwnershipTransferred(currentStorageOwner, newOwner);
        return true;
    }

    function addExchange(
        string memory _name,
        uint256 _factoryId,
        ExchangePlatform _platform,
        ExchangeCategory _category,
        bool _acceptsNativeETH,
        address _platformTokenAddress
    ) external virtual override onlyExchangeAdmin nonReentrant returns (uint16) {
        return LibExchangeHelperStorage.addExchange(
            _name, _factoryId, _platform, _category, _acceptsNativeETH, _platformTokenAddress
        );
    }

    function setExchangeActive(uint16 _exchangeId, bool _isActive)
        external
        virtual
        override
        onlyExchangeAdmin
        nonReentrant
        returns (bool)
    {
        return LibExchangeHelperStorage.setExchangeActive(_exchangeId, _isActive);
    }

    function hasExchange(string memory _name) external view virtual override returns (bool) {
        return LibExchangeHelperStorage.hasExchange(_name);
    }

    function getExchangeById(uint16 id) external view virtual override returns (Exchange memory) {
        return LibExchangeHelperStorage.getExchangeById(id);
    }

    function getExchangeByIdAndFactory(uint16 id, uint256 factoryId)
        external
        view
        virtual
        override
        returns (Exchange memory)
    {
        return LibExchangeHelperStorage.getExchangeByIdAndFactory(id, factoryId);
    }

    function _getContractRegistryAddress() private view returns (address) {
        address registryAddr = LibExchangeHelperStorage.layout().registry;
        if (registryAddr == address(0)) revert EH_ContractRegistryAddressNotSet();
        return registryAddr;
    }

    function addExchangeContract(address _contractAddress, string memory _name, uint16 _contractTypeId)
        external
        virtual
        override
        onlyExchangeAdmin
        nonReentrant
        returns (bool)
    {
        if (_contractAddress == address(0)) revert EH_InvalidAddress();
        address contractRegistryAddr = _getContractRegistryAddress();
        bool success = IContractRegistry(contractRegistryAddr).addContract(_name, _contractAddress, _contractTypeId);
        if (success) {
            emit ExchangeContractAdded(_contractAddress, _name, _contractTypeId);
        }
        return success;
    }

    function setExchangeContractActive(address _contractAddress, bool _isActive)
        external
        virtual
        override
        onlyExchangeAdmin
        nonReentrant
        returns (bool)
    {
        if (_contractAddress == address(0)) revert EH_InvalidAddress();
        address contractRegistryAddr = _getContractRegistryAddress();
        uint16 contractType = IContractRegistry(contractRegistryAddr).setContractActive(_contractAddress, _isActive);
        emit ExchangeContractStatusChanged(_contractAddress, contractType, _isActive);
        return true;
    }

    function detectExchangeType(address addr) external view virtual override returns (ExchangeCategory, bool) {
        return LibExchangeUtils.detectExchangeType(addr);
    }

    function isExchangeType(address addr, ExchangeCategory expectedType)
        external
        view
        virtual
        override
        returns (bool)
    {
        return LibExchangeUtils.isExchangeType(addr, expectedType);
    }

    function getPoolOrPairAddress(PoolParams memory params) external view virtual override returns (address) {
        address contractRegistryAddr = _getContractRegistryAddress();
        return LibExchangeUtils.getPoolOrPairAddress(params, contractRegistryAddr);
    }
}
