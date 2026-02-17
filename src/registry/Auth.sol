// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Config} from "./Config.sol";
import {LibProquint} from "@proquint/LibProquint.sol";
import {IERC173} from "../interface/IERC173.sol";

/**
 * @title Auth
 * @notice Authorization logic for ENS, WNS, Proquint, and address nodes.
 *         Checks ownership via external registry calls, resolver-level approvals,
 *         and registry-level operator approvals. All ownership/auth functions are
 *         so L2 (Auth2) can override to use local _owner mapping.
 */
abstract contract Auth is Config {

    /* ── Approval setters ──────────────────────────────────────────── */

    /** @notice Approve operator for an ENS node. Caller must be ENS owner. */
    function approveENS(bytes32 node, address operator, bool approved) external {
        address owner = _ownerENS(node);
        require(msg.sender == owner, Unauthorized());
        _approval[owner][node][operator] = approved;
        emit Approval(node, operator, approved);
    }

    /** @notice Approve operator for a WNS node. Caller must be WNS owner. */
    function approveWNS(bytes32 node, address operator, bool approved) external {
        address owner = _ownerWEI(node);
        require(msg.sender == owner, Unauthorized());
        _approval[owner][node][operator] = approved;
        emit Approval(node, operator, approved);
    }

    /** @notice Approve operator for a Proquint node. Caller must be Proquint owner. */
    function approveProquint(bytes4 id, address operator, bool approved) external {
        bytes32 node = LibProquint.namehash4(id);
        address owner = _ownerPRO(node);
        require(msg.sender == owner, Unauthorized());
        _approval[owner][node][operator] = approved;
        emit Approval(node, operator, approved);
    }

    /** @notice Approve operator for an address node. Caller must be addr or its ERC-173 owner. */
    function approveAddr(address addr, address operator, bool approved) external {
        require(msg.sender == _ownerOfAddr(addr), Unauthorized());
        bytes32 node = _addressNode(addr);
        _approval[addr][node][operator] = approved;
        emit Approval(node, operator, approved);
    }

    /**
     * @notice Generic approve: caller approves operator for node.
     *         No ownership check; only effective if caller is owner at read time.
     */
    function approve(bytes32 node, address operator, bool approved) external {
        _approval[msg.sender][node][operator] = approved;
        emit Approval(node, operator, approved);
    }

    /** @notice Batch approve operators for nodes. Same no-ownership-check semantics as approve(). */
    function batchApprove(
        bytes32[] calldata nodes,
        address[] calldata operators,
        bool[] calldata approvals
    ) external {
        uint256 len = nodes.length;
        require(len == operators.length && len == approvals.length, LengthMismatch());
        for (uint256 i = 0; i < len;) {
            _approval[msg.sender][nodes[i]][operators[i]] = approvals[i];
            emit Approval(nodes[i], operators[i], approvals[i]);
            unchecked {
                ++i;
            }
        }
    }

    /* ── Ownership lookups ─────────────────────────────────────────── */

    /** @dev Owner of node in ENS registry. Returns address(0) on failure. */
    function _ownerENS(bytes32 node) internal view returns (address owner) {
        try ENS.owner(node) returns (address o) {
            owner = o;
        } catch {}
    }

    /** @dev Owner of node in WNS NameNFT. Returns address(0) on failure. */
    function _ownerWEI(bytes32 node) internal view returns (address owner) {
        try WNS.ownerOf(uint256(node)) returns (address o) {
            owner = o;
        } catch {}
    }

    /** @dev Owner of node in Proquint registry. Returns address(0) on failure. */
    function _ownerPRO(bytes32 node) internal view returns (address owner) {
        try PRO.owner(node) returns (address o) {
            owner = o;
        } catch {}
    }

    /** @dev Resolve owner across WNS → ENS → Proquint (first match wins). */
    function _ownerForNode(bytes32 node) internal view returns (address) {
        address o = _ownerWEI(node);
        if (o != address(0)) return o;
        o = _ownerENS(node);
        if (o != address(0)) return o;
        return _ownerPRO(node);
    }

    /* ── Authorization checks ──────────────────────────────────────── */

    /**
     * @dev Check if msg.sender is owner or resolver-approved for (owner, node).
     *      Checks: direct ownership, node-level approval, address-node approval.
     */
    function _isApprovedOrOwner(address o, bytes32 node) internal view returns (bool) {
        return msg.sender == o
            || _approval[o][node][msg.sender]
            || _approval[o][_addressNode(o)][msg.sender];
    }

    /**
     * @dev Is msg.sender authorized for node? Checks WNS → ENS → Proquint in priority order.
     *      For each namespace: owner, resolver approval, address-node approval, registry operator.
     */
    function _isAuthorized(bytes32 node) internal view returns (bool) {
        address o = _ownerWEI(node);
        if (o != address(0)) {
            if (_isApprovedOrOwner(o, node)) return true;
            try WNS.isApprovedForAll(o, msg.sender) returns (bool ok) {
                return ok;
            } catch {}
            return false;
        }
        o = _ownerENS(node);
        if (o != address(0)) {
            if (_isApprovedOrOwner(o, node)) return true;
            try ENS.isApprovedForAll(o, msg.sender) returns (bool ok) {
                return ok;
            } catch {}
            return false;
        }
        o = _ownerPRO(node);
        if (o != address(0)) {
            if (_isApprovedOrOwner(o, node)) return true;
            try PRO.isApprovedForAll(o, msg.sender) returns (bool ok) {
                return ok;
            } catch {}
            return false;
        }
        return false;
    }

    /** @dev Authorized for ENS node only (owner or approved). */
    function _isAuthorizedENS(bytes32 node) internal view returns (bool) {
        return _isApprovedOrOwner(_ownerENS(node), node);
    }

    /** @dev Authorized for WNS node only (owner or approved). */
    function _isAuthorizedWNS(bytes32 node) internal view returns (bool) {
        return _isApprovedOrOwner(_ownerWEI(node), node);
    }

    /** @dev Authorized for Proquint node only (owner or approved). */
    function _isAuthorizedPRO(bytes32 node) internal view returns (bool) {
        return _isApprovedOrOwner(_ownerPRO(node), node);
    }

    /* ── Address node auth ─────────────────────────────────────────── */

    /** @dev Resolve owner of address: if contract, try ERC-173 owner(); else addr itself. */
    function _ownerOfAddr(address addr) internal view returns (address) {
        if (addr.code.length > 0) {
            try IERC173(addr).owner() returns (address o) {
                if (o != address(0)) return o;
            } catch {}
        }
        return addr;
    }

    /** @dev Authorized for address node: addr itself, its ERC-173 owner, or approved operator. */
    function _isAuthorizedAddr(address addr) internal view returns (bool) {
        if (msg.sender == addr) return true;
        if (addr.code.length > 0) {
            try IERC173(addr).owner() returns (address o) {
                if (o != address(0) && msg.sender == o) return true;
            } catch {}
        }
        return _approval[addr][_addressNode(addr)][msg.sender];
    }
}
