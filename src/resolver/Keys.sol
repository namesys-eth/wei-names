// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IResolverRecords} from "../interface/Interface.sol";

/// @notice Key helpers for resolver records (addr, text, contenthash). Node = bytes32 (namehash or tokenId for .wei).
library Keys {
    function keyContenthash(bytes32 node) internal pure returns (bytes32) {
        return keccak256(abi.encodeWithSelector(IResolverRecords.contenthash.selector, node));
    }

    function keyAddr(bytes32 node) internal pure returns (bytes32) {
        return keccak256(abi.encodeWithSelector(IResolverRecords.addr.selector, node));
    }

    function keyAddrType(bytes32 node, uint256 coinType) internal pure returns (bytes32) {
        return keccak256(
            abi.encodeWithSelector(bytes4(keccak256("addr(bytes32,uint256)")), node, coinType)
        );
    }

    function keyText(bytes32 node, string memory key) internal pure returns (bytes32) {
        return
            keccak256(abi.encodeWithSelector(bytes4(keccak256("text(bytes32,string)")), node, key));
    }

    function keyName(bytes32 node) internal pure returns (bytes32) {
        return keccak256(abi.encodeWithSelector(IResolverRecords.name.selector, node));
    }
}
