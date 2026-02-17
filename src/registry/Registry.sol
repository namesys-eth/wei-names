// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Config} from "./Config.sol";
import {IENS} from "../interface/IENS.sol";
import {IWNS} from "../interface/IWNS.sol";
import {IProquint} from "../interface/IProquint.sol";
import {IRegistry} from "../interface/Interface.sol";
import {LibString} from "solady/utils/LibString.sol";
import {EfficientHashLib} from "solady/utils/EfficientHashLib.sol";

/**
 * @title WNS Unversal Registry
 * @notice Registry contract for the Wei Names namespace
 * @dev Combines ENS, WNS, and Proquint registries and provides a unified interface
 * maintains backwards compatiblity with ENS/js and wallet infra
 */
contract Registry is Config, IRegistry {
    function owner(bytes32 node) external view returns (address _owner) {
        try WNS.ownerOf(uint256(node)) returns (address o) {
            if (o != address(0)) return o;
        } catch {}
        try ENS.owner(node) returns (address o) {
            if (o != address(0)) return o;
        } catch {}
        try PRO.owner(node) returns (address o) {
            if (o != address(0)) return o;
        } catch {}
    }

    function resolver(bytes32 node) external view override returns (address _r) {
        try WNS.ownerOf(uint256(node)) returns (address o) {
            if (o != address(0)) return address(this);
        } catch {}
        try ENS.resolver(node) returns (address r) {
            if (r != address(0)) return r;
        } catch {}
        try PRO.recordExists(node) returns (bool exists) {
            if (exists) return address(this);
        } catch {}
    }

    /// @notice Resolve DNS-encoded name to its resolver address.
    /// @dev Inline DNS decode: loop 1 = labelhashes + TLD classify, loop 2 = TLD-specific resolver walk.
    function resolver(bytes calldata name) external view returns (address _r) {
        // Loop 1: decode DNS wire → labelhashes, count, last label length
        uint256 count;
        uint256 k;
        uint256 lastLen;
        uint256 l = name.length - 1; // skip 0x00 end
        bytes32[] memory lh = new bytes32[](128);
        while (k < l) {
            lastLen = uint8(bytes1(name[k:++k]));
            lh[count++] = EfficientHashLib.hash(name[k:k += lastLen]);
        }
        if (count == 0) return address(0);
        // TLD node from last label hash
        bytes32 node = keccak256(abi.encodePacked(bytes32(0), lh[--count]));

        address _temp;
        bool _local;
        // Address: 42-byte root label "0x..." lowercase hex only
        if (lastLen == 42 && _isLowercaseHexAddr(name[l - 42:l])) {
            _local = true;
        }
        // Proquint: 11-byte root label "cvcvc-cvcvc"
        else if (lastLen == 11) {
            try PRO.recordExists(node) returns (bool exists) {
                if (exists) _local = true;
            } catch {}
        }
        // WNS: walk sub.domain.wei
        else if (node == WEI_NODE) {
            node = EfficientHashLib.hash(abi.encodePacked(node, lh[--count])); // check domain.wei
            try WNS.ownerOf(uint256(node)) returns (address wnsOwner) {
                if (wnsOwner == address(0)) return address(0);
            } catch {
                return address(0);
            }
            _temp = _nodes[node].resolver;
            if (_temp != address(0)) _r = _temp;
            _local = true;
        }
        // Reverse: <hex>.addr.reverse — EIP-181: only 40-char lowercase hex (no 0x).
        else if (node == REVERSE_NODE) {
            node = EfficientHashLib.hash(abi.encodePacked(node, lh[--count])); // addr
            uint256 firstLen = uint8(bytes1(name[0]));
            node = EfficientHashLib.hash(abi.encodePacked(node, _normalizeReverseHexLabel(name[1:1 + firstLen])));
            _temp = _nodes[node].resolver;
            if (_temp != address(0)) _r = _temp;
            if (_r != address(0)) return _r;
            try ENS.resolver(node) returns (address r) {
                if (r != address(0)) return r;
            } catch {}
            return address(this);
        }
        if (_local) {
            while (count > 0) {
                node = EfficientHashLib.hash(abi.encodePacked(node, lh[--count]));
                _temp = _nodes[node].resolver;
                if (_temp != address(0)) _r = _temp;
            }
            return _r == address(0) ? address(this) : _r;
        }
        // fallback: Walk ENS+DNS over ENS
        while (count > 0) {
            node = EfficientHashLib.hash(abi.encodePacked(node, lh[--count]));
            _temp = ENS.resolver(node);
            if (_temp != address(0)) _r = _temp;
        }
    }

    function ttl(bytes32) external pure override returns (uint64) {
        return 0; // always revalidate
    }

    function recordExists(bytes32 node) external view override returns (bool) {
        try ENS.recordExists(node) returns (bool e) {
            if (e) return true;
        } catch {}
        try WNS.ownerOf(uint256(node)) returns (address o) {
            if (o != address(0)) return true;
        } catch {}
        try PRO.recordExists(node) returns (bool e) {
            if (e) return true;
        } catch {}
        return false;
    }

    function sha3HexAddress(address addr) external pure returns (bytes32) {
        return keccak256(bytes(LibString.toHexString(addr)));
    }
}
