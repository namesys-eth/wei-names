// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Auth} from "../registry/Auth.sol";

/**
 * @title AddressResolver
 * @notice Read/write records keyed by (address, key). Write requires the address
 *         itself or an approved operator for that address node.
 */
abstract contract AddressResolver is Auth {
    function read(address addr, bytes32 key) public view returns (bytes memory data) {
        Record storage rec = _recordAt(_addressNode(addr), key);
        uint256 v = rec.latest;
        if (v > 0) return _maybeDecompress(rec.val[v]);
    }

    function read(address addr, bytes32 key, uint256 version)
        public
        view
        returns (bytes memory data)
    {
        return _maybeDecompress(_recordAt(_addressNode(addr), key).val[version]);
    }

    function readBatch(address addr, bytes32[] calldata keys)
        public
        view
        returns (bytes[] memory datas)
    {
        bytes32 node = _addressNode(addr);
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

    function write(address addr, bytes32 key, bytes calldata data) external returns (uint256 v) {
        require(_isAuthorizedAddr(addr), Unauthorized());
        bytes32 node = _addressNode(addr);
        Record storage rec = _recordAt(node, key);
        v = ++rec.latest;
        rec.val[v] = data;
    }

    function write(bytes32 key, bytes calldata data) external returns (uint256 v) {
        bytes32 node = _addressNode(msg.sender);
        Record storage rec = _recordAt(node, key);
        v = ++rec.latest;
        rec.val[v] = data;
    }

    function writeBatch(address addr, bytes32[] calldata keys, bytes[] calldata datas) external {
        require(_isAuthorizedAddr(addr), Unauthorized());
        require(keys.length == datas.length, LengthMismatch());
        bytes32 node = _addressNode(addr);
        uint256 len = keys.length;
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                Record storage rec = _recordAt(node, keys[i]);
                rec.val[++rec.latest] = datas[i];
            }
        }
    }
}
