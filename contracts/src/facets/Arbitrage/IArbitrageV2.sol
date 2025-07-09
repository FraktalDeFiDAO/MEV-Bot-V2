// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActionSwapParams} from "../ExchangeHelper/LibExchangeActions.sol";

// Represents a potential arbitrage opportunity between two pools.
// The contract will figure out the tokens and path.
// We include the exchange IDs so the contract can look up the correct exchange info.
struct ArbitragePoolPair {
    uint16 exchangeIdA;
    address poolA;
    uint16 exchangeIdB;
    address poolB;
}

// A fully resolved, profitable arbitrage path ready for execution.
struct ResolvedArbitragePath {
    bool profitable;
    address loanAsset;
    uint256 loanAmount;
    ActionSwapParams legA;
    ActionSwapParams legB;
    uint256 expectedProfit;
}

// Custom errors for the new facet and library.
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

    /**
     * @notice Analyzes and executes a batch of arbitrage opportunities defined by pairs of pools.
     * @param opportunities An array of pool pairs to analyze and execute if profitable.
     */
    function executePoolPairArbitrage(ArbitragePoolPair[] calldata opportunities) external;

    /**
     * @notice A view-only function to assess an opportunity without executing it.
     * @param opportunity The pair of pools to analyze.
     * @return A struct containing the resolved, profitable path, if one exists.
     */
    function assessOpportunity(ArbitragePoolPair calldata opportunity) external view returns (ResolvedArbitragePath memory);
}