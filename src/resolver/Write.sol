// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReadResolver} from "./Read.sol";
import {AddressResolver} from "./Address.sol";

/**
 * @title WriteResolver
 * @notice Write records by (node, key). Namespace-specific variants enforce
 *         ENS-only or WNS-only authorization. Composes Read + Address.
 */
abstract contract WriteResolver is ReadResolver, AddressResolver {
    /** @notice Write record for node (generic auth across ENS/WNS/PRO). */
    function write(bytes32 node, bytes32 key, bytes calldata data) external returns (uint256 v) {
        require(_isAuthorized(node), Unauthorized());
        return _write(node, key, data);
    }

    function writeENS(bytes32 node, bytes32 key, bytes calldata data) external returns (uint256 v) {
        require(_isAuthorizedENS(node), Unauthorized());
        return _write(node, key, data);
    }

    function writeWNS(bytes32 node, bytes32 key, bytes calldata data) external returns (uint256 v) {
        require(_isAuthorizedWNS(node), Unauthorized());
        return _write(node, key, data);
    }

    function writeBatch(bytes32 node, bytes32[] calldata keys, bytes[] calldata datas) external {
        require(_isAuthorized(node), Unauthorized());
        _writeBatch(node, keys, datas);
    }

    function writeBatchENS(bytes32 node, bytes32[] calldata keys, bytes[] calldata datas) external {
        require(_isAuthorizedENS(node), Unauthorized());
        _writeBatch(node, keys, datas);
    }

    function writeBatchWNS(bytes32 node, bytes32[] calldata keys, bytes[] calldata datas) external {
        require(_isAuthorizedWNS(node), Unauthorized());
        _writeBatch(node, keys, datas);
    }

    function _write(bytes32 node, bytes32 key, bytes calldata data) internal returns (uint256 v) {
        Record storage rec = _recordAt(node, key);
        v = ++rec.latest;
        rec.val[v] = data;
    }

    function _writeBatch(bytes32 node, bytes32[] calldata keys, bytes[] calldata datas) internal {
        require(keys.length == datas.length, LengthMismatch());
        uint256 len = keys.length;
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                Record storage rec = _recordAt(node, keys[i]);
                rec.val[++rec.latest] = datas[i];
            }
        }
    }
}
