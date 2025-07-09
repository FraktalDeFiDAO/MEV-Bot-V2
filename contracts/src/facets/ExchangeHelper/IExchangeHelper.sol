// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum ExchangeCategory {
    Unknown,
    UniswapV2,
    UniswapV3
}

interface IExchangeHelper {
    function detectExchangeType(address pool) external view returns (ExchangeCategory category, bool success);
}