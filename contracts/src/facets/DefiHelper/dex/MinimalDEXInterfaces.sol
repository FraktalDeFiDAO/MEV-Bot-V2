// File: src/facets/DefiHelper/dex/MinimalDEXInterfaces.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28; // Or your project's Solidity version

// --- Balancer V2 Structs and Interface ---

// Describes a single swap step for Balancer V2.
struct BalancerV2SwapRequest {
    bytes32 poolId; // The ID of the pool to swap through.
    uint256 assetInIndex; // The index of the token to send to the pool.
    uint256 assetOutIndex; // The index of the token to receive from the pool.
    uint256 amount; // The amount of assetIn to swap.
    bytes userData; // Arbitrary data to pass to the pool.
}

// Defines how funds are sourced and delivered for a Balancer V2 swap.
struct BalancerV2FundManagement {
    address sender; // The address sending funds to the Vault (often address(this)).
    bool fromInternalBalance; // Whether sender funds are from their internal Vault balance.
    address payable recipient; // The address receiving funds from the Vault.
    bool toInternalBalance; // Whether recipient funds should go to their internal Vault balance.
}

interface IBalancerV2Vault {
    // Function used in LibExchangeActions.sol
    function swap(
        BalancerV2SwapRequest calldata request,
        BalancerV2FundManagement calldata funds,
        uint256 limit, // Minimum amountOut or maximum amountIn
        uint256 deadline
    ) external payable returns (uint256 amountCalculated);

    // Other useful functions (like the one you had in IExchanges.sol)
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

    // Add other IBalancerV2Vault functions as needed by your project
}

// --- Other Minimal DEX Interfaces (ensure these are also present if imported elsewhere) ---

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address guy, uint256 wad) external returns (bool);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
    // Add other IWETH functions as needed
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function WETH() external pure returns (address);
    // Add other IUniswapV2Router functions as needed
}

interface IUniswapV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    // Add other IUniswapV3SwapRouter functions as needed
}

interface ICurvePool {
    function exchange(
        int128 i, // index of token sent
        int128 j, // index of token received
        uint256 dx, // amount of token sent
        uint256 min_dy // min amount of token received
    ) external payable returns (uint256); // Some curve pools return amount, some don't. Adjust if needed.
        // Add other ICurvePool functions as needed
}

// Add any other minimal interfaces that LibExchangeActions.sol or other files might import from here.
