pragma solidity ^0.8.19;

/**
 * @title PoolTypeChecker
 * @author Gemini
 * @notice A general-purpose, gas-efficient utility to check if an arbitrary
 * contract address adheres to common AMM pool interfaces.
 * @dev This version includes hardened checks to ensure that if a pool type is
 * identified, it is guaranteed to have all functions required by the off-chain application.
 */
contract PoolTypeChecker {

    enum PoolType {
        NONE,
        UNISWAP_V2,
        UNISWAP_V3,
        ALGEBRA_V1,
        ALGEBRA_V1_ADAPTIVE,
        ALGEBRA_V1_DBF,
        ALGEBRA_V2_DBF
    }

    // --- Function Selectors for Gas Efficiency ---
    bytes4 private constant V2_GET_RESERVES = bytes4(keccak256("getReserves()"));
    bytes4 private constant V2_KLAST = bytes4(keccak256("kLast()"));
    bytes4 private constant V3_SLOT0 = bytes4(keccak256("slot0()"));
    bytes4 private constant V3_LIQUIDITY = bytes4(keccak256("liquidity()"));
    bytes4 private constant V3_FEE = bytes4(keccak256("fee()"));
    bytes4 private constant ALGEBRA_GLOBAL_STATE = bytes4(keccak256("globalState()"));
    bytes4 private constant ALGEBRA_DATA_STORAGE = bytes4(keccak256("dataStorageOperator()"));
    bytes4 private constant ALGEBRA_BASE_FEE = bytes4(keccak256("baseFee()"));
    bytes4 private constant ALGEBRA_COMMUNITY_FEE_PENDING = bytes4(keccak256("getCommunityFeePending()"));

    // --- SHARED SELECTORS (Required by Go App) ---
    bytes4 private constant TOKEN0 = bytes4(keccak256("token0()"));
    bytes4 private constant TOKEN1 = bytes4(keccak256("token1()"));
    bytes4 private constant FACTORY = bytes4(keccak256("factory()"));

    /**
     * @notice Checks the pool type of a given contract address.
     * @dev The order of checks is important. It proceeds from the most specific
     * interface to the more general ones to ensure accuracy.
     * @param _poolAddress The address of the contract to check.
     * @return The identified pool type.
     */
    function checkPoolType(address _poolAddress) public view returns (PoolType) {
        // First, check if the address has contract code. If not, it can't be a pool.
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(_poolAddress)
        }
        if (codeSize == 0) {
            return PoolType.NONE;
        }
        
        // The order of these checks is critical to prevent misidentification.
        if (isAlgebraV2_DBF(_poolAddress)) return PoolType.ALGEBRA_V2_DBF;
        if (isAlgebraV1_DBF(_poolAddress)) return PoolType.ALGEBRA_V1_DBF;
        if (isAlgebraV1_Adaptive(_poolAddress)) return PoolType.ALGEBRA_V1_ADAPTIVE;
        if (isAlgebraV1(_poolAddress)) return PoolType.ALGEBRA_V1;
        if (isUniswapV3(_poolAddress)) return PoolType.UNISWAP_V3;
        if (isUniswapV2(_poolAddress)) return PoolType.UNISWAP_V2;
        
        return PoolType.NONE;
    }

    /**
     * @notice Checks if a contract implements the full IUniswapV2Pair interface required by the app.
     */
    function isUniswapV2(address _contractAddress) public view returns (bool) {
        bool success;
        // MUST have all functions that the Go multicall requires
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_GET_RESERVES));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(TOKEN0));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(TOKEN1));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(FACTORY));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_KLAST));
        if (!success) return false;

        // Negative checks to prevent matching V3/Algebra pools
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_SLOT0));
        if (success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_GLOBAL_STATE));
        if (success) return false;

        return true;
    }

    /**
     * @notice Checks if a contract implements the full IUniswapV3Pool interface required by the app.
     */
    function isUniswapV3(address _contractAddress) public view returns (bool) {
        bool success;
        // MUST have all functions that the Go multicall requires
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_SLOT0));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_LIQUIDITY));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_FEE));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(TOKEN0));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(TOKEN1));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(FACTORY));
        if (!success) return false;

        // Negative checks
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V2_GET_RESERVES));
        if (success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_GLOBAL_STATE));
        if (success) return false;

        return true;
    }

    /**
     * @notice Checks for an Algebra V1.x-style pool (with immutable fee).
     */
    function isAlgebraV1(address _contractAddress) public view returns (bool) {
        bool success;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_GLOBAL_STATE));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_FEE));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(TOKEN0));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(TOKEN1));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(FACTORY));
        if (!success) return false;

        // Negative checks
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_BASE_FEE));
        if (success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_DATA_STORAGE));
        if (success) return false;

        return true;
    }

    /**
     * @notice Checks for an Algebra V1.9-style pool with adaptive/directional fees.
     */
    function isAlgebraV1_Adaptive(address _contractAddress) public view returns (bool) {
        bool success;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_GLOBAL_STATE));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_DATA_STORAGE));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(TOKEN0));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(TOKEN1));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(FACTORY));
        if (!success) return false;

        // Negative checks
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_FEE));
        if (success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_BASE_FEE));
        if (success) return false;

        return true;
    }

    /**
     * @notice Checks for an Algebra pool with first-gen Direction-Based Fees.
     */
    function isAlgebraV1_DBF(address _contractAddress) public view returns (bool) {
        bool success;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_GLOBAL_STATE));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_BASE_FEE));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_LIQUIDITY));
        if (!success) return false;
        
        // Negative checks
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_COMMUNITY_FEE_PENDING));
        if (success) return false; 
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_DATA_STORAGE));
        if (success) return false; 

        return true;
    }

    /**
     * @notice Checks for an Algebra pool with second-gen Direction-Based Fees.
     */
    function isAlgebraV2_DBF(address _contractAddress) public view returns (bool) {
        bool success;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_GLOBAL_STATE));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_BASE_FEE));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_COMMUNITY_FEE_PENDING));
        if (!success) return false;
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(V3_LIQUIDITY));
        if (!success) return false;

        // Negative checks
        (success, ) = _contractAddress.staticcall(abi.encodeWithSelector(ALGEBRA_DATA_STORAGE));
        if (success) return false; 

        return true;
    }
}