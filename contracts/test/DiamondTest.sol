// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Reuse the base state setup from the consolidated test suite
import "./AllTests.t.sol";

/// @notice Minimal base contract for facet tests
/// @dev Provides the diamond deployment and common utilities via State0_BaseDiamond
abstract contract DiamondTest is State0_BaseDiamond {}
