// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct TokenInfo {
    address token;
    uint8 decimals;
}

interface ITokenHelper {
    function getTokenInfo(address token) external view returns (TokenInfo memory);
}
