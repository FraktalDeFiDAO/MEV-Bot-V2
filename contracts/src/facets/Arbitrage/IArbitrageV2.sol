// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActionSwapParams} from "../ExchangeHelper/LibExchangeActions.sol";

/// Represents a potential arbitrage opportunity between two pools with their associated exchange IDs
struct ArbitragePoolPair {
    uint16 exchangeIdA;
    address poolA;
    uint16 exchangeIdB;
    address poolB;
}

/// A fully resolved, profitable arbitrage path ready for execution
struct ResolvedArbitragePath {
    bool profitable;
    address loanAsset;
    uint256 loanAmount;
    ActionSwapParams legA;
    ActionSwapParams legB;
    uint256 expectedProfit;
}

// Custom errors
error PoolsDoNotShareToken();
error PoolInfoQueryFailed();
error ReserveCalculationError();
error NoProfitablePathFound();

interface IArbitrageV2 {
    event PathAssessed(
        address indexed poolA,
        address indexed poolB,
        bool profitable,
        address loanAsset,
        uint256 loanAmount,
        uint256 expectedProfit
    );

    function executePoolPairArbitrage(ArbitragePoolPair[] calldata opportunities) external;

    function assessOpportunity(ArbitragePoolPair calldata opportunity) external view returns (ResolvedArbitragePath memory);
}
