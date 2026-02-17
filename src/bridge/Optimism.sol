// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Deprecated: OPBridge in ./Base.sol is now a single multi-chain manager.
// Deploy one OPBridge, then call addChain() for each L2:
//   addChain(10, optimismMessenger, l2Target, gasLimit)   // Optimism
//   addChain(8453, baseMessenger, l2Target, gasLimit)     // Base
//   addChain(7777777, zoraMessenger, l2Target, gasLimit)  // Zora
import {OPBridge} from "./Base.sol";
