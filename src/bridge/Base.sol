// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IL1CrossDomainMessenger, IRegistryOwner, IL2ClaimReceiver} from "./OPStackInterfaces.sol";

/// @notice Single OP Stack bridge manager for all Superchain L2s.
/// @dev Deploy once on L1. Owner adds chains via addChain(). Registry (WNS) calls claimOnL2().
///      All OP Stack L2s (Optimism, Base, Zora, Mode, etc.) share the same messenger interface.
contract OPBridge {
    struct Chain {
        address messenger;
        address l2Target;
        uint32 minGasLimit;
    }

    address public immutable registry;
    address public owner;

    mapping(uint256 chainId => Chain) public chains;

    error NotRegistry();
    error NotOwner();
    error UnknownChain(uint256 chainId);
    error Unowned();

    event ChainAdded(uint256 indexed chainId, address messenger, address l2Target, uint32 minGasLimit);
    event ChainRemoved(uint256 indexed chainId);
    event OwnershipTransferred(address indexed prev, address indexed next);

    modifier onlyOwner() {
        require(msg.sender == owner, NotOwner());
        _;
    }

    constructor(address registry_) {
        registry = registry_;
        owner = msg.sender;
    }

    /// @notice Add or update an OP Stack L2 chain.
    function addChain(uint256 chainId, address messenger, address l2Target, uint32 minGasLimit)
        external
        onlyOwner
    {
        chains[chainId] = Chain(messenger, l2Target, minGasLimit);
        emit ChainAdded(chainId, messenger, l2Target, minGasLimit);
    }

    /// @notice Remove an L2 chain.
    function removeChain(uint256 chainId) external onlyOwner {
        delete chains[chainId];
        emit ChainRemoved(chainId);
    }

    /// @notice Called only by registry (WNS) to push ownership claim to an L2.
    function claimOnL2(bytes32 node, uint256 chainId) external {
        require(msg.sender == registry, NotRegistry());
        Chain storage c = chains[chainId];
        require(c.messenger != address(0), UnknownChain(chainId));

        address nodeOwner = IRegistryOwner(registry).owner(node);
        require(nodeOwner != address(0), Unowned());

        bytes memory message = abi.encodeCall(IL2ClaimReceiver.setOwnerFromL1, (node, nodeOwner));
        IL1CrossDomainMessenger(c.messenger).sendMessage(c.l2Target, message, c.minGasLimit);
    }

    /// @notice Transfer ownership of this bridge manager.
    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
