// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {WriteResolver} from "./Write.sol";
import {IResolverRecords} from "../interface/Interface.sol";
import {LibProquint} from "@proquint/LibProquint.sol";

/**
 * @title ReverseResolver
 * @notice Simple bidirectional reverse: addressNode ↔ node.
 *         No multi-root complexity. ENS has its own standalone reverse registry.
 *         WNS and Proquint use their own primary systems as fallback.
 *
 *         Design:
 *         - _nodes[addrNode].reverse[0] = nameNode  (forward: addr → name)
 *         - _nodes[nameNode].reverse[0] = addrNode  (backward: name → addr)
 *         - getReverse(addr) checks: 1) explicit reverse, 2) WNS primaryName, 3) PRO primaryName
 */
abstract contract ReverseResolver is WriteResolver {
    /// @dev Single root key for all reverse mappings.
    bytes32 private constant _REV = bytes32(0);

    event ReverseSet(bytes32 indexed addrNode, bytes32 indexed nameNode);
    event ReverseCleared(bytes32 indexed addrNode);

    /* ── Write ────────────────────────────────────────────────────── */

    /// @notice Set reverse: addr ↔ node. Caller must be authorized for both.
    function setReverse(address addr, bytes32 node) external {
        require(_isAuthorizedAddr(addr), Unauthorized());
        require(_isAuthorized(node), Unauthorized());
        _setReverse(_addressNode(addr), node);
    }

    /// @notice Set reverse for WNS: addr ↔ WNS node.
    function setReverseWNS(address addr, bytes32 node) external {
        require(_isAuthorizedAddr(addr), Unauthorized());
        require(_isAuthorizedWNS(node), Unauthorized());
        _setReverse(_addressNode(addr), node);
    }

    /// @notice Set reverse for proquint: msg.sender ↔ proquint node.
    function setReverse(bytes4 id) external {
        bytes32 node = LibProquint.namehash4(LibProquint.normalize(id));
        require(_isAuthorizedPRO(node), Unauthorized());
        _setReverse(_addressNode(msg.sender), node);
    }

    /// @notice Claim reverse: msg.sender ↔ target node.
    function claimReverse(bytes32 target) external {
        require(_isAuthorized(target), Unauthorized());
        _setReverse(_addressNode(msg.sender), target);
    }

    /// @notice Clear reverse for an address.
    function clearReverse(address addr) external {
        require(_isAuthorizedAddr(addr), Unauthorized());
        _clearReverse(_addressNode(addr));
    }

    /// @notice Clear reverse by node (e.g. when name expires).
    function clearReverseByNode(bytes32 node) external {
        require(_isAuthorized(node), Unauthorized());
        _clearReverse(node);
    }

    /* ── Read ─────────────────────────────────────────────────────── */

    /// @notice Get reverse node for addr. Falls back to WNS primaryName → PRO primaryName.
    function getReverse(address addr) public view returns (bytes32) {
        bytes32 addrNode = _addressNode(addr);
        bytes32 node = _getReverse(addrNode);
        if (node != bytes32(0)) return node;
        // Fallback: WNS primaryName
        try WNS.primaryName(addr) returns (uint256 primary) {
            if (primary != 0) return bytes32(primary);
        } catch {}
        // Fallback: Proquint primaryName
        try PRO.primaryName(addr) returns (bytes32 proNode) {
            if (proNode != bytes32(0)) return proNode;
        } catch {}
        return bytes32(0);
    }

    /// @notice Alias for getReverse (ENS compat).
    function getReverseNode(address addr) public view returns (bytes32) {
        return getReverse(addr);
    }

    /// @notice Get the reverse pair for a given node.
    function getClaim(bytes32 src) public view returns (bytes32) {
        return _getReverse(src);
    }

    /// @notice ENS-compatible name() record reader.
    function name(bytes32 node) external view returns (string memory) {
        bytes32 key = keccak256(abi.encodeWithSelector(IResolverRecords.name.selector, node));
        Record storage rec = _recordAt(node, key);
        uint256 v = rec.latest;
        return v == 0 ? "" : string(_maybeDecompress(rec.val[v]));
    }

    /* ── Internal ─────────────────────────────────────────────────── */

    function _setReverse(bytes32 addrNode, bytes32 nameNode) internal {
        // Clear any existing reverse for this addrNode first
        bytes32 old = _nodes[addrNode].reverse[_REV];
        if (old != bytes32(0)) {
            delete _nodes[old].reverse[_REV];
        }
        _nodes[addrNode].reverse[_REV] = nameNode;
        _nodes[nameNode].reverse[_REV] = addrNode;
        emit ReverseSet(addrNode, nameNode);
    }

    function _getReverse(bytes32 node) internal view returns (bytes32) {
        bytes32 other = _nodes[node].reverse[_REV];
        if (other != bytes32(0) && _nodes[other].reverse[_REV] == node) return other;
        return bytes32(0);
    }

    function _clearReverse(bytes32 node) internal {
        bytes32 other = _nodes[node].reverse[_REV];
        if (other != bytes32(0)) {
            delete _nodes[other].reverse[_REV];
        }
        delete _nodes[node].reverse[_REV];
        emit ReverseCleared(node);
    }
}
