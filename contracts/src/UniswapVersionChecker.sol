// [File: smart-contracts/src/UniswapVersionChecker.sol]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title UniswapVersionChecker
 * @author Gemini
 * @notice A general-purpose, gas-efficient utility to check if an arbitrary
 * contract address adheres to the Uniswap V2 or V3 pool interface.
 * @dev This contract performs checks based on function existence ("duck typing").
 * It uses low-level staticcalls for gas efficiency. This revised version
 * includes more comprehensive checks to reduce the risk of false positives.
 */
contract UniswapVersionChecker {

    enum UniswapVersion {
        NONE,
        V2,
        V3
    }

    // --- Function Selectors for Gas Efficiency ---
    // V2 Selectors
    bytes4 private constant V2_GET_RESERVES = bytes4(keccak256("getReserves()"));
    bytes4 private constant V2_TOKEN0 = bytes4(keccak256("token0()"));
    bytes4 private constant V2_TOKEN1 = bytes4(keccak256("token1()"));
    bytes4 private constant V2_FACTORY = bytes4(keccak256("factory()"));
    bytes4 private constant V2_KLAST = bytes4(keccak256("kLast()"));

    // V3 Selectors
    bytes4 private constant V3_SLOT0 = bytes4(keccak256("slot0()"));
    bytes4 private constant V3_LIQUIDITY = bytes4(keccak256("liquidity()"));
    bytes4 private constant V3_FEE = bytes4(keccak256("fee()"));
    bytes4 private constant V3_FACTORY = bytes4(keccak256("factory()"));
    bytes4 private constant V3_TICK_SPACING = bytes4(keccak256("tickSpacing()"));


    function checkVersion(address _contractAddress) public view returns (UniswapVersion) {
        // We check for V3 first because its interface is more distinct.
        if (isUniswapV3(_contractAddress)) {
            return UniswapVersion.V3;
        }
        if (isUniswapV2(_contractAddress)) {
            return UniswapVersion.V2;
        }
        return UniswapVersion.NONE;
    }

    /**
     * @notice Checks if a contract implements the IUniswapV2Pair interface.
     * @dev A contract is considered V2-compatible if it successfully responds to
     * a suite of V2 functions: `getReserves()`, `token0()`, `token1()`, `factory()`, and `kLast()`.
     * @param _contractAddress The address of the contract to check.
     * @return true if the contract adheres to the V2 interface, false otherwise.
     */
    function isUniswapV2(address _contractAddress) public view returns (bool) {
        bool success;
        // A single failed call is enough to disqualify it.
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_GET_RESERVES));
        if (!success) return false;

        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_TOKEN0));
        if (!success) return false;

        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_TOKEN1));
        if (!success) return false;

        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_FACTORY));
        if (!success) return false;
        
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_KLAST));
        if (!success) return false;

        // As a final check, ensure it does NOT have a unique V3 function like `fee()`.
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_FEE));
        if (success) return false; // If it has fee(), it's likely a V3 or hybrid.

        return true;
    }

    /**
     * @notice Checks if a contract implements the IUniswapV3Pool interface.
     * @dev A contract is considered V3-compatible if it has key V3 functions
     * (`slot0()`, `liquidity()`, `fee()`, `tickSpacing()`) AND does NOT have the primary V2 function `getReserves()`.
     * This prevents V2 forks from being misidentified as V3.
     * @param _contractAddress The address of the contract to check.
     * @return true if the contract adheres to the V3 interface, false otherwise.
     */
    function isUniswapV3(address _contractAddress) public view returns (bool) {
        bool success;

        // --- Positive Checks for key V3 functions ---
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_SLOT0));
        if (!success) return false;

        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_LIQUIDITY));
        if (!success) return false;

        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_FEE));
        if (!success) return false;

        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_TICK_SPACING));
        if (!success) return false;

        // --- Negative Check for a key V2 function ---
        // A true V3 pool must not have getReserves(). This is a critical differentiator.
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_GET_RESERVES));
        if (success) return false;

        return true;
    }
}