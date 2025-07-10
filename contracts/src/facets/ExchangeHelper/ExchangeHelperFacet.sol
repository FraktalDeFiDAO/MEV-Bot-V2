// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ExchangeCategory, PoolParams} from "./IExchangeHelper.sol";
import {LibExchangeUtils} from "./LibExchangeUtils.sol";

contract ExchangeHelperFacet {
    function detectExchangeType(address pool) external view returns (ExchangeCategory category, bool success) {
        return LibExchangeUtils.detectExchangeType(pool);
    }
}
