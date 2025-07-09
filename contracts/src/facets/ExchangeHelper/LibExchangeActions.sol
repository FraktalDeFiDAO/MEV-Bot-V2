// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IExchangeHelper, Exchange, ExchangePlatform} from "./IExchangeHelper.sol";
import {ITokenHelper, TokenInfo} from "../TokenHelper/ITokenHelper.sol";
import {IContractRegistry, ContractInfo} from "../ContractRegistry/IContractRegistry.sol";
import {IWETH, IUniswapV2Router, IUniswapV3SwapRouter, ICurvePool, IBalancerV2Vault, BalancerV2SwapRequest, BalancerV2FundManagement } from "../DefiHelper/dex/MinimalDEXInterfaces.sol";

struct ActionSwapReturn {
    uint256 amountOut;
}

struct ActionSwapParams {
    address exchangeHelperAddress;
    address tokenHelperAddress;
    address contractRegistryAddress;
    address wethAddress;
    uint16 exchangeId;
    uint16 tokenInId;
    uint16 tokenOutId;
    uint256 amountIn;
    uint256 amountOutMin;
    address recipient;
    bytes extraDexParams;
}

// Custom Errors for LibExchangeActions
error LCEA_InvalidRecipient();
error LCEA_InvalidAmountIn();
error LCEA_InvalidHelperOrWETHAddress();
error LCEA_TokenAddressZeroFromHelper();
error LCEA_RouterNotFoundOrInactive();
error LCEA_ExactETHAmountRequired();
error LCEA_ETHSentWithERC20();
error LCEA_CurveIndicesSame();
error LCEA_CurveBalanceNoIncrease();
error LCEA_BalancerPoolIdMissing();
error LCEA_UnsupportedExchangePlatform();
error LCEA_InsufficientOutputReceived();

library LibExchangeActions {
    using SafeERC20 for IERC20;

    function _getActionToken(address tokenHelperAddr, uint16 tokenId, address wethAddr) private view returns (address tokenAddr) {
        if (tokenHelperAddr == address(0) || wethAddr == address(0)) revert LCEA_InvalidHelperOrWETHAddress();
        if (tokenId == 0) {
            return wethAddr;
        }
        TokenInfo memory _token = ITokenHelper(tokenHelperAddr).getTokenById(tokenId);
        tokenAddr = _token.tokenAddress;
        if (tokenAddr == address(0)) revert LCEA_TokenAddressZeroFromHelper();
    }

    function _handleActionInputFunds(address tokenInAddr, uint256 amountIn, address wethAddr, address fromUser) private {
        if (tokenInAddr == wethAddr) {
            if (msg.value > 0) {
                if (msg.value != amountIn) revert LCEA_ExactETHAmountRequired();
                if (amountIn > 0) IWETH(wethAddr).deposit{value: amountIn}();
            } else {
                if (amountIn > 0) IERC20(tokenInAddr).safeTransferFrom(fromUser, address(this), amountIn);
            }
        } else {
            if (msg.value > 0) revert LCEA_ETHSentWithERC20();
            if (amountIn > 0) IERC20(tokenInAddr).safeTransferFrom(fromUser, address(this), amountIn);
        }
    }

    // FIX: Commented out unused wethAddr parameter to silence compiler warning.
    function _handleActionOutputFunds(address tokenOutAddr, uint256 amountOut, address recipient, address /* wethAddr */) private {
        if (amountOut == 0) return;
        if (tokenOutAddr != address(0)) {
            IERC20(tokenOutAddr).safeTransfer(recipient, amountOut);
        }
    }

    /**
     * @notice The main swap function, refactored into a clean dispatcher to prevent "Stack Too Deep" errors.
     * @dev It performs initial checks and then delegates to a specialized internal function based on the exchange platform.
     *      This architectural pattern is crucial for production-level reliability.
     */
    function swap(ActionSwapParams memory params)
        internal
        returns (bool success, ActionSwapReturn memory returnData)
    {
        if (params.recipient == address(0)) revert LCEA_InvalidRecipient();
        if (params.amountIn == 0) revert LCEA_InvalidAmountIn();

        address actualTokenIn = _getActionToken(params.tokenHelperAddress, params.tokenInId, params.wethAddress);
        address actualTokenOut = _getActionToken(params.tokenHelperAddress, params.tokenOutId, params.wethAddress);

        _handleActionInputFunds(actualTokenIn, params.amountIn, params.wethAddress, msg.sender);

        Exchange memory exchangeInfo = IExchangeHelper(params.exchangeHelperAddress).getExchangeById(params.exchangeId);

        uint256 amountOutReceived;

        // Delegate to the appropriate internal swap function.
        if (exchangeInfo.platform == ExchangePlatform.UniswapV2 || exchangeInfo.platform == ExchangePlatform.SushiSwap) {
            amountOutReceived = _swapUniswapV2(params, exchangeInfo, actualTokenIn, actualTokenOut);
        } else if (exchangeInfo.platform == ExchangePlatform.UniswapV3) {
            amountOutReceived = _swapUniswapV3(params, exchangeInfo, actualTokenIn, actualTokenOut);
        } else if (exchangeInfo.platform == ExchangePlatform.CurvePlainPool) {
            amountOutReceived = _swapCurve(params, exchangeInfo, actualTokenIn, actualTokenOut);
        } else if (exchangeInfo.platform == ExchangePlatform.BalancerV2Vault) {
            amountOutReceived = _swapBalancerV2(params, exchangeInfo, actualTokenIn);
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

    // Internal helper to get the router address and approve it for spending the input token.
    function _getRouterAndApprove(ActionSwapParams memory params, Exchange memory exchangeInfo, address tokenToApprove) private returns (address routerAddress) {
        ContractInfo memory routerInfo = IContractRegistry(params.contractRegistryAddress).getContractInfo(exchangeInfo.factoryId);
        routerAddress = routerInfo.addr;

        if (routerAddress == address(0) || !IContractRegistry(params.contractRegistryAddress).isContractActive(routerAddress)) {
            revert LCEA_RouterNotFoundOrInactive();
        }

        if (tokenToApprove != params.wethAddress || (tokenToApprove == params.wethAddress && msg.value == 0)) {
            if (params.amountIn > 0) {
                IERC20(tokenToApprove).forceApprove(routerAddress, params.amountIn);
            }
        }
    }

    // Specialized function for Uniswap V2-style swaps.
    function _swapUniswapV2(ActionSwapParams memory params, Exchange memory exInfo, address actualTokenIn, address actualTokenOut) private returns (uint256) {
        address routerAddress = _getRouterAndApprove(params, exInfo, actualTokenIn);
        address[] memory path = new address[](2);
        path[0] = actualTokenIn;
        path[1] = actualTokenOut;
        uint256[] memory amounts = IUniswapV2Router(routerAddress).swapExactTokensForTokens(
            params.amountIn, params.amountOutMin, path, address(this), block.timestamp
        );
        return amounts[amounts.length - 1];
    }
    
    // Specialized function for Uniswap V3-style swaps.
    function _swapUniswapV3(ActionSwapParams memory params, Exchange memory exInfo, address actualTokenIn, address actualTokenOut) private returns (uint256) {
        address routerAddress = _getRouterAndApprove(params, exInfo, actualTokenIn);
        IUniswapV3SwapRouter.ExactInputSingleParams memory swapParams = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: actualTokenIn, tokenOut: actualTokenOut,
            fee: abi.decode(params.extraDexParams, (uint24)),
            recipient: address(this), deadline: block.timestamp,
            amountIn: params.amountIn, amountOutMinimum: params.amountOutMin,
            sqrtPriceLimitX96: 0
        });
        return IUniswapV3SwapRouter(routerAddress).exactInputSingle(swapParams);
    }
    
    // CORRECTED: This function now properly handles native ETH output from Curve pools.
    function _swapCurve(ActionSwapParams memory params, Exchange memory exInfo, address actualTokenIn, address actualTokenOut) private returns (uint256) {
        address routerAddress = _getRouterAndApprove(params, exInfo, actualTokenIn);
        (int128 curveI, int128 curveJ) = abi.decode(params.extraDexParams, (int128, int128));
        if (curveI == curveJ) revert LCEA_CurveIndicesSame();

        uint256 ethValueToSendCurve = 0;
        if (actualTokenIn == params.wethAddress && exInfo.acceptsNativeETH && msg.value > 0) {
            IWETH(params.wethAddress).withdraw(params.amountIn);
            ethValueToSendCurve = params.amountIn;
        }

        uint256 balBefore = (actualTokenOut == params.wethAddress && exInfo.acceptsNativeETH) 
            ? address(this).balance 
            : IERC20(actualTokenOut).balanceOf(address(this));

        ICurvePool(routerAddress).exchange{value: ethValueToSendCurve}(
            curveI, curveJ, params.amountIn, params.amountOutMin
        );
        
        uint256 balAfter = (actualTokenOut == params.wethAddress && exInfo.acceptsNativeETH)
            ? address(this).balance
            : IERC20(actualTokenOut).balanceOf(address(this));

        if (balAfter <= balBefore) revert LCEA_CurveBalanceNoIncrease();
        return balAfter - balBefore;
    }

    // Specialized function for Balancer V2-style swaps.
    function _swapBalancerV2(ActionSwapParams memory params, Exchange memory exInfo, address actualTokenIn) private returns (uint256) {
        address routerAddress = _getRouterAndApprove(params, exInfo, actualTokenIn);
        (bytes32 poolId, uint256 assetInIdx, uint256 assetOutIdx, bytes memory userData) =
            abi.decode(params.extraDexParams, (bytes32, uint256, uint256, bytes));

        BalancerV2FundManagement memory funds = BalancerV2FundManagement({
            sender: address(this), fromInternalBalance: false,
            recipient: payable(address(this)), toInternalBalance: false
        });
        BalancerV2SwapRequest memory request = BalancerV2SwapRequest({
            poolId: poolId, assetInIndex: assetInIdx, assetOutIndex: assetOutIdx,
            amount: params.amountIn, userData: userData
        });

        if (actualTokenIn == params.wethAddress && msg.value > 0) {
             IERC20(actualTokenIn).forceApprove(routerAddress, params.amountIn);
        }

        return IBalancerV2Vault(routerAddress).swap(request, funds, params.amountOutMin, block.timestamp);
    }
}
