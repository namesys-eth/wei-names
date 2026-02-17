// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev OP Stack L1 messenger (used by L1 bridge contracts).
interface IL1CrossDomainMessenger {
    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external;
}

/// @dev L1 registry view: owner(node) — implemented by WNS (BridgeManager’s backend).
interface IRegistryOwner {
    function owner(bytes32 node) external view returns (address);
}

/// @dev L2 contract that receives ownership sync from L1 (e.g. L2WNS).
interface IL2ClaimReceiver {
    function setOwnerFromL1(bytes32 node, address newOwner) external;
}
