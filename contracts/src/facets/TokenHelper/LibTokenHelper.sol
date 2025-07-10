// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenInfo, ITokenHelper} from "./ITokenHelper.sol";

library LibTokenHelper {
    // Simple in-memory token registry used for tests only
    struct Registry {
        mapping(uint16 => TokenInfo) tokens;
        mapping(address => uint16) ids;
        uint16 nextId;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("lib.token.helper");

    function _storage() private pure returns (Registry storage r) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            r.slot := slot
        }
    }

    function initialize() internal {
        Registry storage r = _storage();
        if (r.nextId == 0) {
            r.nextId = 1; // start ids at 1; 0 reserved for ETH/WETH
        }
    }

    function addToken(address token) internal returns (bool) {
        Registry storage r = _storage();
        if (r.ids[token] != 0) return false;
        r.tokens[r.nextId] = TokenInfo(token, 18);
        r.ids[token] = r.nextId;
        r.nextId++;
        return true;
    }

    function hasToken(address token) internal view returns (bool) {
        Registry storage r = _storage();
        return r.ids[token] != 0;
    }

    function setTokenActive(address, bool) internal returns (bool) {
        return true;
    }

    function activateToken(address) internal returns (bool) {
        return true;
    }

    function deactivateToken(address) internal returns (bool) {
        return true;
    }

    function fetchTokenInfo(address tokenAddress) internal view returns (TokenInfo memory) {
        return TokenInfo(tokenAddress, 18);
    }

    function getTokenById(uint16 id) internal view returns (TokenInfo memory) {
        Registry storage r = _storage();
        return r.tokens[id];
    }

    function getTokenIdByAddress(address tokenAddress) internal view returns (uint16) {
        Registry storage r = _storage();
        return r.ids[tokenAddress];
    }

    function getTokenInfo(address token) internal view returns (TokenInfo memory) {
        return TokenInfo(token, 18);
    }
}
