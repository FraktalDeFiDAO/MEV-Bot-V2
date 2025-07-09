// File: src/facets/ExchangeHelper/LibExchangeActions.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Assuming IExchangeHelper is corrected (uint16 IDs, full Exchange struct)
import {IExchangeHelper, Exchange, ExchangePlatform, ExchangeCategory} from "./IExchangeHelper.sol";
// Assuming ITokenHelper is corrected (events, errors)
import {ITokenHelper, TokenInfo, InvalidTokenId} from "../TokenHelper/ITokenHelper.sol";
// Assuming IContractRegistry is corrected (ContractInfo without isActive, isContractActive function added)
import {IContractRegistry, ContractInfo} from "../ContractRegistry/IContractRegistry.sol";
// Assuming MinimalDEXInterfaces has BalancerV2 structs and correct IBalancerV2Vault
import {
    IWETH,
    IUniswapV2Router,
    IUniswapV3SwapRouter,
    ICurvePool,
    IBalancerV2Vault,
    BalancerV2SwapRequest,
    BalancerV2FundManagement
} from "../DefiHelper/dex/MinimalDEXInterfaces.sol";

import {LibContractRegistry} from "../ContractRegistry/LibContractRegistry.sol";

struct ActionSwapReturn {
    uint256 amountOut;
}

struct ActionSwapParams {
    address exchangeHelperAddress; // Address of the ExchangeHelperFacet
    address tokenHelperAddress; // Address of the TokenHelperFacet
    address contractRegistryAddress; // Address of the ContractRegistryFacet
    address wethAddress; // Address of WETH contract
    uint16 exchangeId; // ID of the exchange from ExchangeHelper
    uint16 tokenInId; // ID of the input token from TokenHelper (0 for ETH/WETH)
    uint16 tokenOutId; // ID of the output token from TokenHelper (0 for ETH/WETH)
    uint256 amountIn; // Amount of tokenIn to swap
    uint256 amountOutMin; // Minimum amount of tokenOut expected
    address recipient; // Address to receive tokenOut
    bytes extraDexParams; // Extra parameters for specific DEXs (e.g., Curve indices, Balancer poolId)
}

// Custom Errors for LibExchangeActions
error LCEA_InvalidRecipient();
error LCEA_InvalidAmountIn();
error LCEA_InvalidHelperOrWETHAddress();
error LCEA_TokenAddressZeroFromHelper();
error LCEA_InvalidHelperAddressForExchange();
error LCEA_RouterNotFoundOrInactive();
error LCEA_ExactETHAmountRequired();
error LCEA_ETHSentWithERC20();
error LCEA_CurveIndicesSame();
error LCEA_CurveBalanceNoIncrease();
error LCEA_BalancerPoolIdMissing();
error LCEA_BalancerIndicesSame();
error LCEA_UnsupportedExchangePlatform();
error LCEA_InsufficientOutputReceived();

library LibExchangeActions {
    using SafeERC20 for IERC20;

    // Fetches token address from TokenHelper. tokenHelperAddr is ITokenHelper.
    // tokenId 0 is reserved for WETH/Native ETH.
    function _getActionToken(address tokenHelperAddr, uint16 tokenId, address wethAddr)
        private
        view
        returns (address tokenAddr)
    {
        if (tokenHelperAddr == address(0) || wethAddr == address(0)) revert LCEA_InvalidHelperOrWETHAddress();
        if (tokenId == 0) {
            // Special case for WETH/Native ETH
            tokenAddr = wethAddr;
            return tokenAddr;
        }
        TokenInfo memory _token = ITokenHelper(tokenHelperAddr).getTokenById(tokenId);
        tokenAddr = _token.tokenAddress;
        if (tokenAddr == address(0)) revert LCEA_TokenAddressZeroFromHelper();
    }

    // Fetches exchange and router details. registryAddr is IContractRegistry.
    function _getActionExchange(address exchangeHelperAddr, address registryAddr, uint16 exchangeId)
        private
        view
        returns (Exchange memory ex, address routerAddr)
    {
        if (exchangeHelperAddr == address(0) || registryAddr == address(0)) {
            revert LCEA_InvalidHelperAddressForExchange();
        }

        ex = IExchangeHelper(exchangeHelperAddr).getExchangeById(exchangeId);

        ContractInfo memory routerInfo = IContractRegistry(registryAddr).getContractInfo(ex.factoryId); // Use IContractRegistry interface
        routerAddr = routerInfo.addr;

        if (routerAddr == address(0) || !IContractRegistry(registryAddr).isContractActive(routerAddr)) {
            // Use IContractRegistry interface
            revert LCEA_RouterNotFoundOrInactive();
        }
        return (ex, routerAddr);
    }

    // Handles input funds: wraps ETH to WETH or transfers ERC20s.
    function _handleActionInputFunds(address tokenInAddr, uint256 amountIn, address wethAddr, address fromUser)
        private
    {
        if (tokenInAddr == wethAddr) {
            // Input is WETH or Native ETH
            if (msg.value > 0) {
                // Native ETH input
                if (msg.value != amountIn) revert LCEA_ExactETHAmountRequired();
                if (amountIn > 0) IWETH(wethAddr).deposit{value: amountIn}();
            } else {
                // WETH already held as ERC20 or amountIn is 0
                if (amountIn > 0) IERC20(tokenInAddr).safeTransferFrom(fromUser, address(this), amountIn);
            }
        } else {
            // ERC20 input (not WETH)
            if (msg.value > 0) revert LCEA_ETHSentWithERC20();
            if (amountIn > 0) IERC20(tokenInAddr).safeTransferFrom(fromUser, address(this), amountIn);
        }
    }

    // Handles output funds: unwraps WETH to ETH or sends ERC20s.
    function _handleActionOutputFunds(address tokenOutAddr, uint256 amountOut, address recipient, address wethAddr)
        private
    {
        if (amountOut == 0) return; // No funds to handle

        if (tokenOutAddr == wethAddr && recipient != address(this)) {
            IERC20(wethAddr).safeTransfer(recipient, amountOut);
        } else if (tokenOutAddr != address(0)) {
            IERC20(tokenOutAddr).safeTransfer(recipient, amountOut);
        }
    }

    function swap(ActionSwapParams memory params) internal returns (bool success, ActionSwapReturn memory returnData) {
        if (params.recipient == address(0)) revert LCEA_InvalidRecipient();
        if (params.amountIn == 0) revert LCEA_InvalidAmountIn();

        address actualTokenIn = _getActionToken(params.tokenHelperAddress, params.tokenInId, params.wethAddress);
        address actualTokenOut = _getActionToken(params.tokenHelperAddress, params.tokenOutId, params.wethAddress);

        _handleActionInputFunds(actualTokenIn, params.amountIn, params.wethAddress, msg.sender);

        (Exchange memory ex, address routerAddress) =
            _getActionExchange(params.exchangeHelperAddress, params.contractRegistryAddress, params.exchangeId);

        // Approve router if tokenIn is an ERC20 (includes WETH if not native ETH input)
        if (actualTokenIn != params.wethAddress || (actualTokenIn == params.wethAddress && msg.value == 0)) {
            // Approve only if amountIn > 0 for ERC20s (including WETH sent as ERC20)
            if (params.amountIn > 0) {
                IERC20(actualTokenIn).forceApprove(routerAddress, params.amountIn);
            }
        }

        uint256 amountOutReceived;

        if (ex.platform == ExchangePlatform.UniswapV2 || ex.platform == ExchangePlatform.SushiSwap) {
            address[] memory path = new address[](2);
            path[0] = actualTokenIn;
            path[1] = actualTokenOut;
            uint256[] memory amounts = IUniswapV2Router(routerAddress).swapExactTokensForTokens(
                params.amountIn, params.amountOutMin, path, address(this), block.timestamp
            );
            amountOutReceived = amounts[amounts.length - 1];
        } else if (ex.platform == ExchangePlatform.UniswapV3) {
            IUniswapV3SwapRouter.ExactInputSingleParams memory swapParams = IUniswapV3SwapRouter.ExactInputSingleParams({
                tokenIn: actualTokenIn,
                tokenOut: actualTokenOut,
                fee: abi.decode(params.extraDexParams, (uint24)),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: params.amountIn,
                amountOutMinimum: params.amountOutMin,
                sqrtPriceLimitX96: 0
            });
            uint256 valueToSendUniV3 = 0;
            // Note: Native ETH handling for Uniswap V3 (valueToSendUniV3) remains complex and
            // depends on specific router capabilities and whether _handleActionInputFunds should
            // conditionally avoid wrapping ETH to WETH. Current logic assumes WETH is used if actualTokenIn is WETH.
            amountOutReceived =
                IUniswapV3SwapRouter(routerAddress).exactInputSingle{value: valueToSendUniV3}(swapParams);
        } else if (ex.platform == ExchangePlatform.CurvePlainPool) {
            (int128 curveI, int128 curveJ) = abi.decode(params.extraDexParams, (int128, int128));
            if (curveI == curveJ) revert LCEA_CurveIndicesSame();

            uint256 ethValueToSendCurve = 0;
            uint256 amountToExchangeCurve = params.amountIn;

            if (actualTokenIn == params.wethAddress && ex.acceptsNativeETH) {
                if (msg.value > 0 && msg.value == params.amountIn) {
                    IWETH(params.wethAddress).withdraw(params.amountIn);
                    ethValueToSendCurve = params.amountIn;
                }
            }
            uint256 balBefore = (actualTokenOut == params.wethAddress && ex.acceptsNativeETH && params.tokenOutId == 0)
                ? address(this).balance
                : IERC20(actualTokenOut).balanceOf(address(this));

            ICurvePool(routerAddress).exchange{value: ethValueToSendCurve}(
                curveI, curveJ, amountToExchangeCurve, params.amountOutMin
            );

            uint256 balAfter = (actualTokenOut == params.wethAddress && ex.acceptsNativeETH && params.tokenOutId == 0)
                ? address(this).balance
                : IERC20(actualTokenOut).balanceOf(address(this));
            if (balAfter <= balBefore && params.amountIn > 0) revert LCEA_CurveBalanceNoIncrease();
            amountOutReceived = balAfter - balBefore;
        } else if (ex.platform == ExchangePlatform.BalancerV2Vault) {
            (bytes32 poolIdBal, uint256 assetInIdxBal, uint256 assetOutIdxBal, bytes memory userDataBal) =
                abi.decode(params.extraDexParams, (bytes32, uint256, uint256, bytes));
            if (poolIdBal == bytes32(0)) revert LCEA_BalancerPoolIdMissing();
            if (assetInIdxBal == assetOutIdxBal) revert LCEA_BalancerIndicesSame();

            BalancerV2FundManagement memory fundsBal = BalancerV2FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            });
            BalancerV2SwapRequest memory requestBal = BalancerV2SwapRequest({
                poolId: poolIdBal,
                assetInIndex: assetInIdxBal,
                assetOutIndex: assetOutIdxBal,
                amount: params.amountIn,
                userData: userDataBal
            });
            // Specific approval for WETH to Balancer Vault if ETH was deposited (msg.value > 0)
            // This case is not covered by the generic approval block if msg.value > 0.
            if (actualTokenIn == params.wethAddress && msg.value > 0 && params.amountIn > 0) {
                IERC20(actualTokenIn).forceApprove(routerAddress, params.amountIn);
            }

            amountOutReceived =
                IBalancerV2Vault(routerAddress).swap(requestBal, fundsBal, params.amountOutMin, block.timestamp);
        } else {
            revert LCEA_UnsupportedExchangePlatform();
        }

        if (amountOutReceived < params.amountOutMin) {
            revert LCEA_InsufficientOutputReceived();
        }

        _handleActionOutputFunds(actualTokenOut, amountOutReceived, params.recipient, params.wethAddress);

        returnData.amountOut = amountOutReceived;
        success = true;
        return (success, returnData);
    }
}
