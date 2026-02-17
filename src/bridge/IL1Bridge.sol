// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev L1 per-chain bridge: only registry (WNS) may call claimOnL2.
interface IL1Bridge {
    function claimOnL2(bytes32 node, uint256 chainId) external;
}
