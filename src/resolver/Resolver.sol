// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IResolver, IResolverRecords, IERC165} from "../interface/Interface.sol";
import {Auth} from "../registry/Auth.sol";
import {RedirectResolver} from "./Redirect.sol";
import {ReverseResolver} from "./Reverse.sol";
import {ProquintResolver} from "./Proquint.sol";
import {OffchainResolver} from "./Offchain.sol";
import {Utils} from "./Utils.sol";
import {EfficientHashLib} from "solady/utils/EfficientHashLib.sol";

/**
 * @title Resolver
 * @notice ENSIP-10 / EIP-3668 wildcard resolver for ENS, WNS, Proquint, and address nodes.
 *         Composes all resolver features: read/write, redirect, reverse, proquint, offchain.
 *         resolve() walks DNS-encoded names, classifies TLD, and falls back to CCIP-Read.
 */
contract Resolver is
    Auth,
    RedirectResolver,
    ReverseResolver,
    ProquintResolver,
    OffchainResolver,
    IResolver
{
    error InvalidRequest();

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == Resolver.resolve.selector || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice ENSIP-10/ERC-3668 wildcard resolve.
    /// Node types: Address, Proquint, WNS (.wei), Reverse (.addr.reverse), ENS.
    /// Priority: 1) direct record at node, 2) redirect, 3) TLD walk → activeNode, 4) wildcard, 5) recordhash/CCIP-Read.
    function resolve(bytes calldata name, bytes calldata request)
        external
        view
        returns (bytes memory)
    {
        bytes4 selector = bytes4(request[0:4]);
        bytes32 node = bytes32(request[4:36]);
        bytes32 key = EfficientHashLib.hash(request);

        // 1) Fast path: direct record at node, then redirect
        {
            Record storage rec = _recordAt(node, key);
            if (rec.latest > 0) return _maybeDecompress(rec.val[rec.latest]);
        }
        {
            (bytes32 resNode, uint256 rver) = _resolveRedirect(node, key);
            if (resNode != node) {
                Record storage rec =
                    _recordAt(resNode, EfficientHashLib.hash(abi.encodePacked(selector, resNode, request[36:])));
                uint256 v = rver > 0 ? rver : rec.latest;
                if (v > 0) return _maybeDecompress(rec.val[v]);
            }
        }

        // 2) DNS decode: labelhashes + domain + path
        uint256 count;
        uint256 lastLen;
        bytes32[] memory lh = new bytes32[](128); // Full DNS limit 255 bytes max = <128 labels+dots
        string memory domain;
        string memory path;
        uint256 l = name.length - 1;
        {
            uint256 k = 0;
            lastLen = uint8(bytes1(name[k]));
            bytes memory label = name[k:k += lastLen];
            lh[count++] = EfficientHashLib.hash(label);
            domain = string(label);
            path = domain;
            while (k < l) {
                lastLen = uint8(bytes1(name[k++]));
                label = name[k:k += lastLen];
                lh[count++] = EfficientHashLib.hash(label);
                domain = string.concat(domain, ".", string(label));
                path = string.concat(string(label), "/", path);
            }
        }
        if (count == 0) return "";

        // 3) TLD classify + walk (mirrors Registry.resolver(bytes))
        bytes32 walkNode = EfficientHashLib.hash(bytes32(0), lh[--count]);
        bytes32 activeNode;
        bool isENS;

        // Address: 42-byte root "0x..." lowercase hex
        if (lastLen == 42 && _isLowercaseHexAddr(name[l - 42:l])) {
            activeNode = walkNode;
        }
        // Proquint: 11-byte root "cvcvc-cvcvc"
        else if (lastLen == 11) {
            try PRO.recordExists(walkNode) returns (bool exists) {
                if (exists) activeNode = walkNode;
            } catch {}
        }
        // WNS: .wei — advance to domain.wei, try NameNFT fallback
        else if (walkNode == WEI_NODE) {
            walkNode = EfficientHashLib.hash(walkNode, lh[--count]); // DNS walk to domain.wei
            activeNode = walkNode;
            if (_isWNSSelector(selector) && _nodes[walkNode].resolver == address(0)) {
                (bool ok, bytes memory data) = address(WNS).staticcall(request);
                if (ok && data.length > 0) return data;
            }
        }
        // Reverse: <hex>.addr.reverse — EIP-181: only 40-char lowercase hex (no 0x).
        else if (walkNode == REVERSE_NODE) {
            walkNode = EfficientHashLib.hash(walkNode, lh[--count]); // addr
            uint256 firstLen = uint8(bytes1(name[0]));
            walkNode = EfficientHashLib.hash(walkNode, _normalizeReverseHexLabel(name[1:1 + firstLen]));
            activeNode = walkNode;
        }
        // ENS fallthrough
        else {
            isENS = true;
        }

        // 4) Walk remaining subdomains, track deepest node with resolver == this
        while (count > 0) {
            walkNode = EfficientHashLib.hash(walkNode, lh[--count]);
            if (_nodes[walkNode].resolver == address(this)) {
                activeNode = walkNode;
            }
        }

        // 5) Try at activeNode: direct → redirect → wildcard
        if (activeNode != bytes32(0)) {
            Record storage arec = _recordAt(activeNode, key);
            if (arec.latest > 0) return _maybeDecompress(arec.val[arec.latest]);

            (bytes32 resNode, uint256 rver) = _resolveRedirect(activeNode, key);
            if (resNode != activeNode) {
                Record storage rrec = _recordAt(
                    resNode,
                    EfficientHashLib.hash(abi.encodePacked(request[:4], resNode, request[36:]))
                );
                uint256 v = rver > 0 ? rver : rrec.latest;
                if (v > 0) return _maybeDecompress(rrec.val[v]);
            }
        }

        // 6) Recordhash / CCIP-Read (try leaf node first, then activeNode)
        return _tryCCIPRead(name, request, node, activeNode, isENS, domain, path);
    }

    /// @dev CCIP-Read fallback: check recordhash at node/activeNode, revert with OffchainLookup if found.
    function _tryCCIPRead(
        bytes calldata name,
        bytes calldata request,
        bytes32 node,
        bytes32 activeNode,
        bool isENS,
        string memory domain,
        string memory path
    ) internal view returns (bytes memory) {
        bytes32 rhNode = node;
        bytes memory rh = _getRecordhash(rhNode);
        if (rh.length == 0 && activeNode != bytes32(0) && activeNode != node) {
            rhNode = activeNode;
            rh = _getRecordhash(rhNode);
        }
        if (rh.length > 0) {
            bytes4 selector = bytes4(request[0:4]);
            if (selector == IResolverRecords.contenthash.selector) {
                return _maybeDecompress(rh);
            }
            address nodeOwner = isENS ? _ownerENS(rhNode) : _ownerForNode(rhNode);
            string memory recType = Utils.selectorToJson(request);
            string memory hostSuffix = isENS ? ".limo" : "";
            string[] memory urls =
                Utils.buildOffchainUrls(domain, path, recType, rh, hostSuffix, _gateways);
            bytes32 checkhash = keccak256(
                abi.encodePacked(
                    address(this), blockhash(block.number - 1), nodeOwner, request
                )
            );
            revert OffchainLookup(
                address(this),
                urls,
                abi.encodeWithSelector(Resolver.resolve.selector, name, request),
                this.__callback.selector,
                abi.encode(rhNode, block.number - 1, checkhash, domain, recType, request)
            );
        }

        return "";
    }

    /// @dev NameNFT supports: addr(bytes32), addr(bytes32,uint256), contenthash(bytes32), text(bytes32,string)
    function _isWNSSelector(bytes4 selector) internal pure returns (bool) {
        return selector == IResolverRecords.addr.selector
            || selector == bytes4(keccak256("addr(bytes32,uint256)"))
            || selector == IResolverRecords.contenthash.selector
            || selector == IResolverRecords.text.selector;
    }
}
