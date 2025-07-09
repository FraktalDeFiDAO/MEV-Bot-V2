// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActionSwapParams} from "../facets/ExchangeHelper/LibExchangeActions.sol";

// --- AAVE INTERFACES ---
interface IPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IPoolAddressesProvider {
    function getPool() external view returns (address);
}

// --- STORAGE STRUCT ---

struct AppStorage {
    address WETH_ADDRESS;
    IPoolAddressesProvider AAVE_POOL_ADDRESSES_PROVIDER;
    mapping(address => uint256) profitTracker;
}

// --- LIBRARY & ERRORS ---

library LibAppStorage {
    bytes32 constant APP_STORAGE_SLOT = keccak256("fraktal.protocol.app.storage");

    function getStorage() internal pure returns (AppStorage storage s) {
        bytes32 position = APP_STORAGE_SLOT;
        assembly {
            s.slot := position
        }
    }
}

// --- ROLE CONSTANTS ---
bytes32 constant ARBITRAGE_ADMIN_ROLE = keccak256("ARBITRAGE_ADMIN_ROLE");

// --- CUSTOM ERRORS FOR ARBITRAGE FACET ---
error AE_ZeroAmount(string message);
error AE_InvalidCallback(string message);
error AE_PathMismatch(string message);
error AE_CallerNotAavePool();
error AE_ArrayLengthMismatch();
error AE_FlashLoanFailed();
error AE_NotEnoughProfit();
error AE_InsufficientBalance(string message);