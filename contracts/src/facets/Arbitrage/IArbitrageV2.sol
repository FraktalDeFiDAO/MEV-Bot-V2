// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Thrown when two pools do not share a common token for arbitrage
error PoolsDoNotShareToken();
/// @notice Thrown when pool metadata cannot be queried
error PoolInfoQueryFailed();
/// @notice Thrown when reserves cannot be calculated from pool data
error ReserveCalculationError();

/// @notice Thrown when no profitable arbitrage path is found
error NoProfitablePathFound();

/// @notice Represents a pair of liquidity pools used for arbitrage
struct ArbitragePoolPair {
    address pool0;
    address pool1;
}

/// @notice Represents a resolved path for arbitrage swaps
struct ResolvedArbitragePath {
    address[] swapPath;
}

/// @dev Minimal interface for arbitrage helpers used by other facets
interface IArbitrageV2 {
    function findProfitablePath(
        ArbitragePoolPair calldata pools,
        uint256 amountIn
    ) external view returns (ResolvedArbitragePath memory path);
}
