// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Auth} from "../registry/Auth.sol";

/**
 * @title ReadResolver
 * @notice Read-only record access by (node, key) with optional version pinning.
 *         Does not follow redirects — use resolve(name, request) for redirect-aware lookup.
 */
abstract contract ReadResolver is Auth {
    /** @notice Read latest record for (node, key). No redirect resolution. */
    function read(bytes32 node, bytes32 key) public view returns (bytes memory data) {
        Record storage rec = _recordAt(node, key);
        uint256 v = rec.latest;
        if (v > 0) return _maybeDecompress(rec.val[v]);
    }

    function read(bytes32 node, bytes32 key, uint256 version)
        public
        view
        returns (bytes memory data)
    {
        return _maybeDecompress(_recordAt(node, key).val[version]);
    }

    function readBatch(bytes32 node, bytes32[] calldata keys)
        public
        view
        returns (bytes[] memory datas)
    {
        uint256 len = keys.length;
        datas = new bytes[](len);
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                Record storage rec = _recordAt(node, keys[i]);
                uint256 v = rec.latest;
                if (v > 0) datas[i] = _maybeDecompress(rec.val[v]);
            }
        }
    }

    function readBatch(bytes32 node, bytes32[] calldata keys, uint256[] calldata versions)
        public
        view
        returns (bytes[] memory datas)
    {
        require(keys.length == versions.length, LengthMismatch());
        uint256 len = keys.length;
        datas = new bytes[](len);
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                datas[i] = _maybeDecompress(_recordAt(node, keys[i]).val[versions[i]]);
            }
        }
    }
}
