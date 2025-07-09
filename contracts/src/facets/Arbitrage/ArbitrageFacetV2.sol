// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IArbitrageV2, ArbitragePoolPair, ResolvedArbitragePath, NoProfitablePathFound} from "./IArbitrageV2.sol";
import {LibArbitrageCalculator} from "./LibArbitrageCalculator.sol";
import {LibAppStorage} from "../../libraries/LibAppStorage.sol";
import {ActionSwapParams} from "../ExchangeHelper/LibExchangeActions.sol";
import {ITokenHelper} from "../TokenHelper/ITokenHelper.sol";
import {IUniswapV3Pool} from "../../interfaces/IUniswapV3.sol";
import {ExchangeCategory} from "../ExchangeHelper/IExchangeHelper.sol";
import {ArbitrageFacet} from "./ArbitrageFacet.sol";

/**
 * @title ArbitrageFacetV2
 * @author Gemini
 * @notice An advanced facet for automatically analyzing and executing arbitrage opportunities between pairs of liquidity pools.
 * @dev This contract acts as an orchestrator. It uses LibArbitrageCalculator to find profitable paths
 *      and then calls the original ArbitrageFacet's execution logic to perform the flash loan and swaps.
 *      This promotes code reuse and separation of concerns.
 */
contract ArbitrageFacetV2 is IArbitrageV2, ReentrancyGuard {
    /**
     * @notice Main entry point for executing a batch of arbitrage opportunities.
     * @dev Loops through each provided pool pair, assesses it for profitability, and executes if a valid opportunity is found.
     *      Uses a try/catch block to ensure that one failed assessment does not halt the entire batch.
     * @param opportunities An array of pool pairs to analyze.
     */
    function executePoolPairArbitrage(ArbitragePoolPair[] calldata opportunities)
        external
        override
        nonReentrant
    {
        for (uint i = 0; i < opportunities.length; i++) {
            try this.assessOpportunity(opportunities[i]) returns (ResolvedArbitragePath memory path) {
                // This block executes only if assessOpportunity finds a profitable path and does not revert.
                if (path.profitable) {
                    emit PathAssessed(
                        opportunities[i].poolA,
                        opportunities[i].poolB,
                        true,
                        path.loanAsset,
                        path.loanAmount,
                        path.expectedProfit
                    );

                    // Call the original `executeAaveArbitrage` function on the diamond.
                    // This reuses the existing, tested flash loan callback mechanism.
                    ArbitrageFacet(address(this)).executeAaveArbitrage(
                        path.loanAsset,
                        path.loanAmount,
                        path.legA,
                        path.legB,
                        0 // We set min profit to 0 because we've already assessed it on-chain.
                    );
                }
            } catch {
                // If assessOpportunity reverts (e.g., NoProfitablePathFound), we catch it and continue.
                // This makes the batch execution robust.
                emit PathAssessed(opportunities[i].poolA, opportunities[i].poolB, false, address(0), 0, 0);
                // Continue to the next opportunity in the loop.
            }
        }
    }

    /**
     * @notice A view-only function to assess an opportunity without executing it.
     * @dev This is useful for off-chain bots to quickly check if an on-chain execution is likely to succeed.
     * @param opportunity The pair of pools to analyze.
     * @return A struct containing the resolved, profitable path, if one exists. Reverts if no profitable path is found.
     */
    function assessOpportunity(ArbitragePoolPair calldata opportunity)
        public
        view
        override
        returns (ResolvedArbitragePath memory)
    {
        // 1. Get standardized information for both pools.
        LibArbitrageCalculator.PoolInfo memory infoA = LibArbitrageCalculator.getPoolInfo(opportunity.poolA);
        LibArbitrageCalculator.PoolInfo memory infoB = LibArbitrageCalculator.getPoolInfo(opportunity.poolB);

        // 2. Determine the arbitrage path (which token is the pivot).
        (address tokenX, address tokenY, address pivotToken) =
            LibArbitrageCalculator.findArbitragePath(infoA, infoB);

        // 3. Assess both possible directions for the arbitrage.
        // Path 1: Loan X, swap X -> Pivot (in pool A), swap Pivot -> X (in pool B)
        (bool profitable1, ResolvedArbitragePath memory path1) =
            _assessSingleDirection(tokenX, pivotToken, infoA, infoB, opportunity);

        // Path 2: Loan Y, swap Y -> Pivot (in pool B), swap Pivot -> Y (in pool A)
        (bool profitable2, ResolvedArbitragePath memory path2) =
            _assessSingleDirection(tokenY, pivotToken, infoB, infoA, opportunity);

        // 4. Return the most profitable path or revert if neither is profitable.
        if (profitable1 && (!profitable2 || path1.expectedProfit > path2.expectedProfit)) {
            return path1;
        }
        if (profitable2) {
            return path2;
        }

        revert NoProfitablePathFound();
    }

    /**
     * @dev Internal view function to check one direction of an arbitrage and construct the execution parameters.
     * @param startToken The token to flash loan and start the arbitrage with.
     * @param pivotToken The intermediate token to swap through.
     * @param pool1 The first pool in the swap path (Start -> Pivot).
     * @param pool2 The second pool in the swap path (Pivot -> Start).
     * @param opportunity The original pool pair data containing exchange IDs and addresses.
     * @return A boolean indicating profitability and the fully constructed ResolvedArbitragePath.
     */
    function _assessSingleDirection(
        address startToken,
        address pivotToken,
        LibArbitrageCalculator.PoolInfo memory pool1,
        LibArbitrageCalculator.PoolInfo memory pool2,
        ArbitragePoolPair calldata opportunity
    ) private view returns (bool, ResolvedArbitragePath memory) {
        // Calculate a conservative loan amount to minimize slippage.
        uint256 loanAmount = LibArbitrageCalculator.calculateLoanAmount(pool1, startToken);
        if (loanAmount == 0) return (false, ResolvedArbitragePath(false, address(0), 0, ActionSwapParams(address(0),address(0),address(0),address(0),0,0,0,0,0,address(0),""), ActionSwapParams(address(0),address(0),address(0),address(0),0,0,0,0,0,address(0),""), 0));

        // Quote the two legs of the swap.
        uint256 pivotAmount = LibArbitrageCalculator.quote(loanAmount, pool1, startToken);
        if (pivotAmount == 0) return (false, ResolvedArbitragePath(false, address(0), 0, ActionSwapParams(address(0),address(0),address(0),address(0),0,0,0,0,0,address(0),""), ActionSwapParams(address(0),address(0),address(0),address(0),0,0,0,0,0,address(0),""), 0));
        
        uint256 finalAmount = LibArbitrageCalculator.quote(pivotAmount, pool2, pivotToken);

        // Account for the Aave flash loan fee (0.09%).
        uint256 flashFee = (loanAmount * 9) / 10000;

        if (finalAmount > loanAmount + flashFee) {
            uint256 profit = finalAmount - (loanAmount + flashFee);

            // If profitable, construct the full ActionSwapParams for execution.
            ITokenHelper tokenHelper = ITokenHelper(address(this));
            uint16 startTokenId = tokenHelper.getTokenIdByAddress(startToken);
            uint16 pivotTokenId = tokenHelper.getTokenIdByAddress(pivotToken);

            bytes memory extraParamsA;
            if (pool1.category == ExchangeCategory.UniswapV3) {
                extraParamsA = abi.encode(IUniswapV3Pool(opportunity.poolA).fee());
            }

            bytes memory extraParamsB;
            if (pool2.category == ExchangeCategory.UniswapV3) {
                extraParamsB = abi.encode(IUniswapV3Pool(opportunity.poolB).fee());
            }

            address diamondAddr = address(this);
            address wethAddr = LibAppStorage.getStorage().WETH_ADDRESS;

            ActionSwapParams memory legA = ActionSwapParams(
                diamondAddr, diamondAddr, diamondAddr, wethAddr,
                opportunity.exchangeIdA, startTokenId, pivotTokenId,
                loanAmount, 0, diamondAddr, extraParamsA
            );
            ActionSwapParams memory legB = ActionSwapParams(
                diamondAddr, diamondAddr, diamondAddr, wethAddr,
                opportunity.exchangeIdB, pivotTokenId, startTokenId,
                pivotAmount, 0, diamondAddr, extraParamsB
            );

            return (true, ResolvedArbitragePath(true, startToken, loanAmount, legA, legB, profit));
        }

        // Return a default "not profitable" struct.
        return (false, ResolvedArbitragePath(false, address(0), 0, ActionSwapParams(address(0),address(0),address(0),address(0),0,0,0,0,0,address(0),""), ActionSwapParams(address(0),address(0),address(0),address(0),0,0,0,0,0,address(0),""), 0));
    }
}