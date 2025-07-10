// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ExchangeCategory, ExchangePlatform, PoolParams} from "./IExchangeHelper.sol";
import {LibExchangeUtils} from "./LibExchangeUtils.sol";

contract ExchangeHelperFacet {
    function detectExchangeType(address pool) external view returns (ExchangeCategory category, bool success) {
        return LibExchangeUtils.detectExchangeType(pool);
    }

    function initializeExchangeHelper(address, address, address) external {}

    function addExchange(
        string memory,
        uint256,
        ExchangePlatform,
        ExchangeCategory,
        bool,
        address
    ) external returns (bool) {
        return true;
    }

    function hasExchange(string memory) external pure returns (bool) {
        return true;
    }
}
