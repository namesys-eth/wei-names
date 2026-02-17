// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Auth} from "./Auth.sol";
import {LibProquint} from "@proquint/LibProquint.sol";
import {IL1Bridge} from "../bridge/IL1Bridge.sol";

/**
 * @title Bridge
 * @notice L1 bridge manager: routes node ownership claims to L2 via chain-specific
 *         bridge contracts. Only contract owner can configure chain bridges.
 */
abstract contract Bridge is Auth {
    /** @dev chainId => L1 bridge contract (implements IL1Bridge). */
    mapping(uint256 chainId => address bridge) public chainBridges;

    error UnknownChain(uint256 chainId);

    event ChainBridgeSet(uint256 indexed chainId, address indexed bridge);
    event Bridged(bytes32 indexed node, uint256 indexed chainId, address indexed owner);

    /** @dev Lookup bridge for chain, call claimOnL2, emit event. */
    function _bridge(bytes32 node, uint256 chainId) internal {
        address b = chainBridges[chainId];
        require(b != address(0), UnknownChain(chainId));
        IL1Bridge(b).claimOnL2(node, chainId);
        emit Bridged(node, chainId, msg.sender);
    }

    /** @notice Set bridge contract for a chain. Only contract owner. */
    function setChainBridge(uint256 chainId, address _bridge) external onlyOwner {
        chainBridges[chainId] = _bridge;
        emit ChainBridgeSet(chainId, _bridge);
    }

    /** @notice Bridge an ENS node to L2. */
    function bridgeENS(bytes32 node, uint256 chainId) external {
        require(_isAuthorizedENS(node), Unauthorized());
        _bridge(node, chainId);
    }

    /** @notice Bridge a WNS node to L2. */
    function bridgeWNS(bytes32 node, uint256 chainId) external {
        require(_isAuthorizedWNS(node), Unauthorized());
        _bridge(node, chainId);
    }

    /** @notice Bridge a Proquint node to L2. */
    function bridgeProquint(bytes4 id, uint256 chainId) external {
        bytes32 node = LibProquint.namehash4(id);
        require(_isAuthorizedPRO(node), Unauthorized());
        _bridge(node, chainId);
    }
}
