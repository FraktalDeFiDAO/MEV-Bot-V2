// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import "forge-std/Script.sol";

// Using explicit lib paths and aliases to prevent any ambiguity or collision.
// These contracts will be compiled with solc v0.7.6.

// --- Crypto-Algebra V1.9 ---
import {IAlgebraFactory as IAlgebraFactory_V19} from "lib/cryptoalgebra/Algebra/V1.9/src/core/contracts/interfaces/IAlgebraFactory.sol";
import {AlgebraPool as AlgebraPool_V19} from "lib/cryptoalgebra/Algebra/V1.9/src/core/contracts/AlgebraPool.sol";
import {SwapRouter as SwapRouter_V19} from "lib/cryptoalgebra/Algebra/V1.9/src/periphery/contracts/SwapRouter.sol";

// --- Crypto-Algebra V1.9 with Directional Fee ---
import {IAlgebraFactory as IAlgebraFactory_V19_DF} from "lib/cryptoalgebra/Algebra/V1.9-direction-based-fee/src/core/contracts/interfaces/IAlgebraFactory.sol";
import {AlgebraPool as AlgebraPool_V19_DF} from "lib/cryptoalgebra/Algebra/V1.9-direction-based-fee/src/core/contracts/AlgebraPool.sol";
import {SwapRouter as SwapRouter_V19_DF} from "lib/cryptoalgebra/Algebra/V1.9-direction-based-fee/src/periphery/contracts/SwapRouter.sol";

contract Bindings07 is Script {
    function run() external {}
}