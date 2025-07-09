// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolAddressesProvider} from "../interfaces/IPoolAddressesProvider.sol";
import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2.sol";
import {IUniswapV3Pool} from "../interfaces/IUniswapV3.sol";

struct ActionSwapParams {
    address router;
    address[] path;
    uint256 amountIn;
    uint256 amountOutMin;
}

contract ArbitrageFacet {
    IPoolAddressesProvider public provider;

    constructor(IPoolAddressesProvider _provider) {
        provider = _provider;
    }

    function executeAaveArbitrage(address _loanAsset, uint256 _loanAmount, ActionSwapParams calldata legA, ActionSwapParams calldata legB) external {
        // Placeholder: this is a stub for compilation
        _loanAsset; _loanAmount; legA; legB;
    }
}
