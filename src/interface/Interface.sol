// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @notice ENSIP-10 / EIP-3668 cross-chain resolver
interface IExtendedResolver {
    function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory);
    function addr(bytes32 node, uint256 coinType) external view returns (bytes memory);
}

/// @notice ENSIP-10 / EIP-3668 resolver entrypoint.
interface IResolver is IERC165 {
    function resolve(bytes calldata name, bytes calldata request)
        external
        view
        returns (bytes memory);
}

/// @notice Minimal record-resolver selectors used for `Keys` (addr/contenthash/name).
/// @dev This interface exists only to reference selectors; implementations may live elsewhere.
interface IResolverRecords {
    function addr(bytes32 node) external view returns (address);
    function contenthash(bytes32 node) external view returns (bytes memory);
    function name(bytes32 node) external view returns (string memory);
    function text(bytes32 node, string calldata key) external view returns (string memory);
}

/// @notice Unified registry: .eth (ENS) + .wei (NameNFT) + proquint + address-node primitive (namespace gateway)
interface IRegistry {
    function owner(bytes32 node) external view returns (address);
    function resolver(bytes32 node) external view returns (address);
    function ttl(bytes32 node) external view returns (uint64);
    function recordExists(bytes32 node) external view returns (bool);
}

/// @notice Address-node primitive: node = namehash(0, keccak256(hex(addr)))
interface IRegistryAddressNode {
    function addressNode(address addr) external pure returns (bytes32);
    function resolverForAddress(address addr) external view returns (address);
    function recordExistsForAddress(address addr) external view returns (bool);
}

/// @notice ERC721 safe transfer callback (EIP-721).
interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

/// @notice Simple bidirectional reverse: addr ↔ node.
interface IReverseResolver {
    function setReverse(address addr, bytes32 node) external;
    function setReverseWNS(address addr, bytes32 node) external;
    function setReverse(bytes4 id) external;
    function claimReverse(bytes32 target) external;
    function clearReverse(address addr) external;
    function clearReverseByNode(bytes32 node) external;
    function getReverse(address addr) external view returns (bytes32);
    function getReverseNode(address addr) external view returns (bytes32);
    function getClaim(bytes32 src) external view returns (bytes32);
    function name(bytes32 node) external view returns (string memory);
}
