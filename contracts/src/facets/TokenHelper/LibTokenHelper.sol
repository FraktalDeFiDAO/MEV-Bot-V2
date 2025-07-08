// [IDEMPOTENT INITIALIZER => smart-contracts/src/facets/TokenHelper/LibTokenHelper.sol]
// SPDX-License-Identifier: Fraktal-Protocol
pragma solidity ^0.8.0;

import {IERC20Metadata} from "lib/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    ITokenHelper,
    TokenInfo,
    TokenAdded,
    TokenStatusChanged,
    TokenHelperStorage,
    TokenAlreadyExists,
    TokenNotFoundByAddress,
    TokenNotFoundById,
    InvalidTokenId,
    TH_MetadataFetchFailed,
    TH_MaxTokenCapacityReached,
    TH_AlreadyInitialized
} from "./ITokenHelper.sol";

library LibTokenHelper {
    bytes32 constant STORAGE_POSITION = keccak256("fraktal.protocol.mev.helper.storage");

    function layout() internal pure returns (TokenHelperStorage storage l) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }

    // MODIFIED for Idempotency
    function initialize() internal {
        TokenHelperStorage storage l = layout();
        if (l.initialized) {
            return; // Silently return if already initialized
        }
        l.initialized = true;
    }

    function _fetchTokenMetadataInternal(address tokenAddress) private view returns (TokenInfo memory token) {
        try IERC20Metadata(tokenAddress).name() returns (string memory name) {
            token.name = name;
            token.symbol = IERC20Metadata(tokenAddress).symbol();
            token.decimals = IERC20Metadata(tokenAddress).decimals();
            token.tokenAddress = tokenAddress;
        } catch { /* Returns empty TokenInfo if not a valid ERC20Metadata contract */ }
        return token;
    }

    function addToken(address tokenAddress) internal returns (bool) {
        if (tokenAddress == address(0)) revert InvalidTokenId();
        TokenHelperStorage storage l = layout();
        if (!l.initialized) revert TH_AlreadyInitialized(); // Revert if not initialized before use

        uint16 existingOneBasedId = l.tokenAddressToIdMap[tokenAddress];
        if (existingOneBasedId != 0) {
            TokenInfo storage existingToken = l.tokenIdToInfoMap[existingOneBasedId - 1];
            if (existingToken.isActive) {
                revert TokenAlreadyExists(tokenAddress);
            } else {
                existingToken.isActive = true;
                emit TokenStatusChanged(tokenAddress, existingOneBasedId - 1, true);
                return true;
            }
        }

        TokenInfo memory newMetaData = _fetchTokenMetadataInternal(tokenAddress);
        if (newMetaData.tokenAddress == address(0)) {
            revert TH_MetadataFetchFailed(tokenAddress);
        }

        uint16 newZeroBasedId = l.tokensCount;
        if (newZeroBasedId == type(uint16).max) revert TH_MaxTokenCapacityReached();

        newMetaData.isActive = true;
        l.tokenIdToInfoMap[newZeroBasedId] = newMetaData;
        l.tokenAddressToIdMap[tokenAddress] = newZeroBasedId + 1;
        l.tokensCount++;
        emit TokenAdded(tokenAddress, newZeroBasedId, newMetaData.name, newMetaData.symbol, newMetaData.decimals);
        return true;
    }

    function fetchTokenInfo(address tokenAddress) internal view returns (TokenInfo memory) {
        if (tokenAddress == address(0)) revert InvalidTokenId();
        TokenHelperStorage storage l = layout();
        if (!l.initialized) revert TH_AlreadyInitialized();
        uint16 storedIdOneBased = l.tokenAddressToIdMap[tokenAddress];
        if (storedIdOneBased == 0) revert TokenNotFoundByAddress(tokenAddress);
        return l.tokenIdToInfoMap[storedIdOneBased - 1];
    }

    function hasToken(address tokenAddress) internal view returns (bool) {
        if (tokenAddress == address(0)) return false;
        TokenHelperStorage storage l = layout();
        if (!l.initialized) return false; // If not initialized, has no tokens
        uint16 storedIdOneBased = l.tokenAddressToIdMap[tokenAddress];
        if (storedIdOneBased == 0) return false;
        return l.tokenIdToInfoMap[storedIdOneBased - 1].isActive;
    }

    function getTokenById(uint16 id_zeroBased) internal view returns (TokenInfo memory) {
        TokenHelperStorage storage l = layout();
        if (!l.initialized) revert TH_AlreadyInitialized();
        if (id_zeroBased >= l.tokensCount) {
            revert TokenNotFoundById(id_zeroBased);
        }
        TokenInfo memory token = l.tokenIdToInfoMap[id_zeroBased];
        if (!token.isActive) {
            revert TokenNotFoundById(id_zeroBased);
        }
        return token;
    }

    function getTokenIdByAddress(address tokenAddress) internal view returns (uint16) {
        if (tokenAddress == address(0)) revert InvalidTokenId();
        TokenHelperStorage storage l = layout();
        if (!l.initialized) revert TH_AlreadyInitialized();
        uint16 storedIdOneBased = l.tokenAddressToIdMap[tokenAddress];
        if (storedIdOneBased == 0) revert TokenNotFoundByAddress(tokenAddress);

        uint16 id_zeroBased = storedIdOneBased - 1;
        if (id_zeroBased >= l.tokensCount || !l.tokenIdToInfoMap[id_zeroBased].isActive) {
            // Bounds check
            revert TokenNotFoundByAddress(tokenAddress);
        }
        return id_zeroBased;
    }

    function setTokenActive(address tokenAddress, bool _isActive) internal returns (bool) {
        if (tokenAddress == address(0)) revert InvalidTokenId();
        TokenHelperStorage storage l = layout();
        if (!l.initialized) revert TH_AlreadyInitialized();
        uint16 storedIdOneBased = l.tokenAddressToIdMap[tokenAddress];

        if (storedIdOneBased == 0) {
            if (_isActive) {
                return addToken(tokenAddress);
            } else {
                return true;
            }
        }

        uint16 id_zeroBased = storedIdOneBased - 1;
        TokenInfo storage tokenToUpdate = l.tokenIdToInfoMap[id_zeroBased];

        if (tokenToUpdate.isActive == _isActive) return true;

        tokenToUpdate.isActive = _isActive;
        emit TokenStatusChanged(tokenAddress, id_zeroBased, _isActive);
        return true;
    }

    function activateToken(address tokenAddress) internal returns (bool) {
        return setTokenActive(tokenAddress, true);
    }

    function deactivateToken(address tokenAddress) internal returns (bool) {
        return setTokenActive(tokenAddress, false);
    }
}
