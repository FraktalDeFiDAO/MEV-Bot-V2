// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenInfo, ITokenHelper} from "./ITokenHelper.sol";

library LibTokenHelper {
    function getTokenInfo(address token) internal view returns (TokenInfo memory) {
        uint8 decimals = 18;
        return TokenInfo(token, decimals);
    }
}
