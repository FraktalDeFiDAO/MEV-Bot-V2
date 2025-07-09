// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../libraries/LibAppStorage.sol";
import "../ExchangeHelper/LibExchangeActions.sol";
import "../TokenHelper/LibTokenHelper.sol";
import {IContractRegistry} from "../ContractRegistry/IContractRegistry.sol";

// Interface for the flash loan receiver
interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

struct ArbitrageCallbackData {
    address loanAsset;
    uint256 loanAmount;
    ActionSwapParams legA;
    ActionSwapParams legB;
    uint256 minNetProfitLoanAsset;
    address initiator;
}

contract ArbitrageFacet is IFlashLoanReceiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event ArbitrageExecuted(
        address indexed loanAsset,
        uint256 loanAmount,
        address tokenIntermediate,
        uint256 amountIntermediateReceived,
        uint256 amountLoanAssetRecovered,
        uint256 profit,
        address indexed initiator
    );

    event ProfitWithdrawn(address indexed token, address indexed to, uint256 amount);

    function initialize(address _wethAddress, address _aavePoolAddressesProviderRegistry) external {
        AppStorage storage s = LibAppStorage.getStorage();
        // This initializer should only be callable once
        require(s.WETH_ADDRESS == address(0), "Already initialized");
        s.WETH_ADDRESS = _wethAddress;
        s.AAVE_POOL_ADDRESSES_PROVIDER = IPoolAddressesProvider(_aavePoolAddressesProviderRegistry);
    }

    function executeAaveArbitrage(
        address _loanAsset,
        uint256 _loanAmount,
        ActionSwapParams calldata _legA,
        ActionSwapParams calldata _legB,
        uint256 _minNetProfitLoanAsset
    ) external nonReentrant {
        AppStorage storage s = LibAppStorage.getStorage();
        if (_loanAmount == 0) revert AE_ZeroAmount("Loan amount must be > 0");
        if (_legA.recipient != address(this) || _legB.recipient != address(this)) {
            revert AE_InvalidCallback("Leg recipient must be this contract");
        }

        // Path validation
        TokenInfo memory tokenInInfoA = LibTokenHelper.getTokenById(_legA.tokenInId);
        TokenInfo memory tokenOutInfoB = LibTokenHelper.getTokenById(_legB.tokenOutId);
        if (tokenInInfoA.tokenAddress != _loanAsset || tokenOutInfoB.tokenAddress != _loanAsset) {
            revert AE_PathMismatch("Leg A in / Leg B out must be loan asset");
        }

        TokenInfo memory tokenOutInfoA = LibTokenHelper.getTokenById(_legA.tokenOutId);
        TokenInfo memory tokenInInfoB = LibTokenHelper.getTokenById(_legB.tokenInId);
        if (tokenOutInfoA.tokenAddress != tokenInInfoB.tokenAddress) {
            revert AE_PathMismatch("Leg A out != Leg B in (must be intermediate asset)");
        }
        if (tokenInInfoA.tokenAddress == tokenOutInfoA.tokenAddress) {
            revert AE_PathMismatch("Loan and intermediate asset cannot be same");
        }

        bytes memory params = abi.encode(
            ArbitrageCallbackData({
                loanAsset: _loanAsset,
                loanAmount: _loanAmount,
                legA: _legA,
                legB: _legB,
                minNetProfitLoanAsset: _minNetProfitLoanAsset,
                initiator: msg.sender
            })
        );

        address[] memory assets = new address[](1);
        assets[0] = _loanAsset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _loanAmount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // No debt tokenization

        IPool aavePool = IPool(s.AAVE_POOL_ADDRESSES_PROVIDER.getPool());
        aavePool.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata receivedAmounts,
        uint256[] calldata premiums,
        address, // initiator from Aave is not used
        bytes calldata paramsData
    ) external override returns (bool) {
        AppStorage storage s = LibAppStorage.getStorage();
        if (msg.sender != s.AAVE_POOL_ADDRESSES_PROVIDER.getPool()) revert AE_CallerNotAavePool();
        if (assets.length != 1) revert AE_ArrayLengthMismatch();

        ArbitrageCallbackData memory data = abi.decode(paramsData, (ArbitrageCallbackData));

        if (data.loanAsset != assets[0]) {
            revert AE_PathMismatch("Callback loan asset mismatch with Aave provided asset.");
        }
        if (data.loanAmount != receivedAmounts[0]) revert AE_FlashLoanFailed();

        // Setup Leg A
        ActionSwapParams memory legAParams = data.legA;
        legAParams.amountIn = receivedAmounts[0];
        legAParams.exchangeHelperAddress = address(this);
        legAParams.tokenHelperAddress = address(this);
        legAParams.contractRegistryAddress = address(this);
        legAParams.wethAddress = s.WETH_ADDRESS;

        // Execute Leg A
        (, ActionSwapReturn memory legAReturn) = LibExchangeActions.swap(legAParams);
        uint256 intermediateAmountReceived = legAReturn.amountOut;
        if (intermediateAmountReceived == 0 && legAParams.amountIn > 0) revert AE_FlashLoanFailed();

        // Setup Leg B
        ActionSwapParams memory legBParams = data.legB;
        legBParams.amountIn = intermediateAmountReceived;
        legBParams.exchangeHelperAddress = address(this);
        legBParams.tokenHelperAddress = address(this);
        legBParams.contractRegistryAddress = address(this);
        legBParams.wethAddress = s.WETH_ADDRESS;

        // Execute Leg B
        (, ActionSwapReturn memory legBReturn) = LibExchangeActions.swap(legBParams);
        uint256 finalLoanAssetAmount = legBReturn.amountOut;
        if (finalLoanAssetAmount == 0 && legBParams.amountIn > 0) revert AE_FlashLoanFailed();

        // Profit Check & Repayment
        uint256 totalRepaymentAmount = data.loanAmount + premiums[0];
        if (finalLoanAssetAmount < totalRepaymentAmount + data.minNetProfitLoanAsset) {
            revert AE_NotEnoughProfit();
        }
        uint256 actualProfit = finalLoanAssetAmount - totalRepaymentAmount;
        s.profitTracker[data.loanAsset] += actualProfit;

        // Repay Aave
        IERC20(data.loanAsset).approve(s.AAVE_POOL_ADDRESSES_PROVIDER.getPool(), totalRepaymentAmount);

        // Emit event
        address intermediateTokenAddress = LibTokenHelper.getTokenById(legAParams.tokenOutId).tokenAddress;
        emit ArbitrageExecuted(
            data.loanAsset,
            data.loanAmount,
            intermediateTokenAddress,
            intermediateAmountReceived,
            finalLoanAssetAmount,
            actualProfit,
            data.initiator
        );

        return true;
    }

    function withdrawTokens(address _tokenAddress, address _to, uint256 _amount) external {
        // This should be guarded by access control, which we will handle in the AccessControlFacet
        // For now, let's assume only an admin can call this.
        if (_to == address(0)) revert AE_InvalidCallback("Invalid recipient for withdraw");
        uint256 amountToWithdraw = _amount;
        if (_tokenAddress == address(0)) {
            // ETH
            uint256 balance = address(this).balance;
            if (amountToWithdraw == 0) amountToWithdraw = balance;
            if (amountToWithdraw > balance) revert AE_InsufficientBalance("Insufficient ETH balance");
            payable(_to).transfer(amountToWithdraw);
        } else {
            // ERC20
            uint256 balance = IERC20(_tokenAddress).balanceOf(address(this));
            if (amountToWithdraw == 0) amountToWithdraw = balance;
            if (amountToWithdraw > balance) revert AE_InsufficientBalance("Insufficient token balance");
            IERC20(_tokenAddress).safeTransfer(_to, amountToWithdraw);
        }
        emit ProfitWithdrawn(_tokenAddress, _to, amountToWithdraw);
    }
}
