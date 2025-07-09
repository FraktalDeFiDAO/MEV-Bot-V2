// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ExchangeHelperStorage, Exchange} from "./IExchangeHelper.sol";

library LibExchangeHelperStorage {
    bytes32 internal constant NAMESPACE = keccak256("exchange.helper.storage");

    function getStorage() internal pure returns (ExchangeHelperStorage storage s) {
        bytes32 slot = NAMESPACE;
        assembly { s.slot := slot }
    }

    function setExchange(string memory name, Exchange memory ex) internal {
        ExchangeHelperStorage storage s = getStorage();
        s.exchangesInfo[name] = ex;
    }
}
