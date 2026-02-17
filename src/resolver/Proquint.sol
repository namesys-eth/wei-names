// SPDX-License-Identifier: WTFPL.ETH
pragma solidity ^0.8.30;

import {Auth} from "../registry/Auth.sol";
import {LibProquint} from "@proquint/LibProquint.sol";

/**
 * @title ProquintResolver
 * @notice Read/write records keyed by Proquint id (bytes4). Authorization
 *         checked against the Proquint registry owner.
 */
abstract contract ProquintResolver is Auth {
    function write(bytes4 id, bytes32 key, bytes calldata data) external returns (uint256 v) {
        bytes32 node = LibProquint.namehash4(id);
        require(_isAuthorizedPRO(node), Unauthorized());
        Record storage rec = _recordAt(node, key);
        v = ++rec.latest;
        rec.val[v] = data;
    }

    function writeBatch(bytes4 id, bytes32[] calldata keys, bytes[] calldata datas) external {
        bytes32 node = LibProquint.namehash4(id);
        require(_isAuthorizedPRO(node), Unauthorized());
        require(keys.length == datas.length, LengthMismatch());
        uint256 len = keys.length;
        for (uint256 i = 0; i < len;) {
            Record storage rec = _recordAt(node, keys[i]);
            rec.val[++rec.latest] = datas[i];
            unchecked { ++i; }
        }
    }

    function read(bytes4 id, bytes32 key) external view returns (bytes memory) {
        Record storage rec = _recordAt(LibProquint.namehash4(id), key);
        uint256 v = rec.latest;
        if (v == 0) return "";
        return _maybeDecompress(rec.val[v]);
    }

    function read(bytes4 id, bytes32 key, uint256 version) external view returns (bytes memory) {
        Record storage rec = _recordAt(LibProquint.namehash4(id), key);
        uint256 current = rec.latest;
        uint256 v = (version == 0 || version > current) ? current : version;
        if (v == 0) return "";
        return _maybeDecompress(rec.val[v]);
    }

    function readBatch(bytes4 id, bytes32[] calldata keys)
        external
        view
        returns (bytes[] memory datas)
    {
        bytes32 node = LibProquint.namehash4(id);
        uint256 len = keys.length;
        datas = new bytes[](len);
        for (uint256 i = 0; i < len;) {
            Record storage rec = _recordAt(node, keys[i]);
            uint256 v = rec.latest;
            if (v > 0) datas[i] = _maybeDecompress(rec.val[v]);
            unchecked { ++i; }
        }
    }
}
