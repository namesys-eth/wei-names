// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IENS} from "../interface/IENS.sol";
import {IWNS} from "../interface/IWNS.sol";
import {IProquint} from "../interface/IProquint.sol";
import {ILibZip} from "../interface/ILibZip.sol";
import {EfficientHashLib} from "solady/utils/EfficientHashLib.sol";
import {LibBytes} from "solady/utils/LibBytes.sol";
import {LibString} from "solady/utils/LibString.sol";
import {LibZip} from "solady/utils/LibZip.sol";

/**
 * @title Config
 * @notice Core configuration: constants, structs, mappings, ownership, and helpers
 *         shared by all resolver and registry contracts.
 */
abstract contract Config {
    /* ── Namespace root nodes ─────────────────────────────────────── */

    /// @dev namehash("wei")
    bytes32 public constant WEI_NODE =
        0xa82820059d5df798546bcc2985157a77c3eef25eba9ba01899927333efacbd6f;
    /// @dev namehash("eth")
    bytes32 public constant ETH_NODE =
        0x93cdeb708b7545dc668eb9280176169f1f33ecdfe72ee77d8dd83386c7e92a7e;
    /// @dev namehash("reverse")
    bytes32 public constant REVERSE_NODE =
        0xa097f6721ce401e757d1223a763fef49b8b5f90bb18567ddb86fd205dff71d34;
    /// @dev namehash("addr.reverse")
    bytes32 public constant ADDR_REVERSE_NODE =
        0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

    /* ── External contracts ───────────────────────────────────────── */

    IWNS internal constant WNS = IWNS(0x0000000000696760E15f265e828DB644A0c242EB);
    IENS internal constant ENS = IENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
    IProquint internal PRO = IProquint(0x0000000000000000000000000000000000000000);
    address internal constant ENS_REVERSE_REGISTRAR = 0xa58E81fe9b61B5c3fE2AFD33CF304c454AbFc7Cb;

    /* ── Structs ───────────────────────────────────────────────────── */

    /**
     * @dev Versioned data store.
     * Append-only: each write increments `latest`.
     * val[version] => raw bytes (may be libzip/calldata compressed).
     * !important data for ENS like resolver is abi encoded
     * eg, addr = abi.encode(address(...))
     */
    struct Record {
        mapping(uint256 version => bytes data) val;
        uint256 latest;
    }

    /**
     * @dev Redirect pointer: target node + version.
     * target  — destination node for redirect resolution.
     * version — version of the destination node's record to use.
     */
    struct Pointer {
        bytes32 target;
        uint256 version;
    }

    /**
     * @dev Per-key entry inside a node.
     * record   — versioned record data for this key.
     * redirect — pointer to another node's records.
     */
    struct Entry {
        Record record;
        Pointer redirect;
    }

    /**
     * @dev Per-node storage.
     * resolver          — custom resolver address (0 = use default).
     * entries           — key => Entry (versioned data + redirect per key).
     * redirectAllowlist — source => key => expiry timestamp.
     *   0 = disabled, type(uint256).max = forever, else block.timestamp < expiry.
     * reverse           — root => paired node (bidirectional reverse mapping).
     */
    struct Node {
        address resolver;
        mapping(bytes32 key => Entry) entries;
        mapping(bytes32 source => mapping(bytes32 key => uint256 expiry)) redirectAllowlist;
        mapping(bytes32 root => bytes32 paired) reverse;
    }

    /* ── State ─────────────────────────────────────────────────────── */

    /// @dev node => per-node storage (records, redirects, reverse, resolver).
    mapping(bytes32 node => Node) internal _nodes;

    /// @dev Resolver approvals: approval[owner][node][operator] => bool.
    mapping(address owner => mapping(bytes32 node => mapping(address operator => bool))) internal
        _approval;

    /// @dev ERC-173 contract owner (gateway admin, bridge config). Named `_contractOwner`
    ///      to avoid shadowing `owner(bytes32)` in Registry.
    address private _contractOwner;

    /// @dev Cached checksummed address(this) for off-chain signature messages.
    string internal _resolverAddr;

    /* ── Errors & Events ───────────────────────────────────────────── */

    error BadWireFormat();
    error Unauthorized();
    error Unowned();
    error LengthMismatch();

    /** @dev EIP-3668 CCIP-Read: revert to trigger off-chain gateway lookup. */
    error OffchainLookup(
        address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData
    );

    event Approval(bytes32 indexed node, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /* ── Ownership (ERC-173) ────────────────────────────────────────── */

    function owner() public view returns (address) {
        return _contractOwner;
    }

    modifier onlyOwner() {
        require(msg.sender == _contractOwner, Unauthorized());
        _;
    }

    function _initOwner(address newOwner) internal {
        require(_contractOwner == address(0), "Already initialized");
        require(newOwner != address(0), "Invalid owner");
        _contractOwner = newOwner;
        _resolverAddr = LibString.toHexStringChecksummed(address(this));
        emit OwnershipTransferred(address(0), newOwner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        address prev = _contractOwner;
        _contractOwner = newOwner;
        emit OwnershipTransferred(prev, newOwner);
    }

    /** @notice Set the Proquint registry address. Only contract owner. */
    function setProquint(address pro) external onlyOwner {
        PRO = IProquint(pro);
    }

    /* ── Internal helpers ──────────────────────────────────────────── */

    /** @dev Hash an address into its node: keccak256(0x00, keccak256(toHexString(addr))). */
    function _addressNode(address addr) internal pure returns (bytes32) {
        bytes32 labelhash = EfficientHashLib.hash(bytes(LibString.toHexString(addr)));
        return EfficientHashLib.hash(bytes32(0), labelhash);
    }

    /** @dev Transparently decompress if data starts with a LibZip selector. */
    function _maybeDecompress(bytes memory data) internal pure returns (bytes memory) {
        if (data.length < 5) return data;
        bytes4 sig = bytes4(bytes32(data));
        if (sig == ILibZip.cdDecompress.selector) {
            return LibZip.cdDecompress(LibBytes.slice(data, 4));
        }
        if (sig == ILibZip.flzDecompress.selector) {
            return LibZip.flzDecompress(LibBytes.slice(data, 4));
        }
        return data;
    }

    /** @dev Get versioned data storage for a (node, key) pair. */
    function _recordAt(bytes32 node, bytes32 key) internal view returns (Record storage) {
        return _nodes[node].entries[key].record;
    }

    /** @notice Read decompressed record data at a specific version. */
    function dataStorage(bytes32 node, bytes32 key, uint256 version)
        external
        view
        virtual
        returns (bytes memory)
    {
        return _maybeDecompress(_recordAt(node, key).val[version]);
    }

    /** @notice Latest version number for a (node, key) pair. */
    function latestVersion(bytes32 node, bytes32 key) external view returns (uint256) {
        return _recordAt(node, key).latest;
    }

    /**
     * @dev ENS reverse (EIP-181): only 40-char lowercase hex (no 0x).
     *      If label is exactly 40 bytes and all 0-9 or a-f, return keccak256(label).
     *      Otherwise return hash(label) so resolution does not match the ENS reverse node.
     */
    function _normalizeReverseHexLabel(bytes calldata label) internal pure returns (bytes32) {
        if (label.length != 40) return EfficientHashLib.hash(label);
        for (uint256 i = 0; i < 40;) {
            bytes1 c = label[i];
            if (c >= 0x30 && c <= 0x39) { unchecked { ++i; } continue; } // 0-9
            if (c >= 0x61 && c <= 0x66) { unchecked { ++i; } continue; } // a-f only
            return EfficientHashLib.hash(label); // uppercase or invalid
        }
        return keccak256(label);
    }

    /** @dev Validate 42-byte label is "0x" + 40 lowercase hex chars (DNS auto-lowercases). */
    function _isLowercaseHexAddr(bytes calldata label) internal pure returns (bool result) {
        assembly ("memory-safe") {
            function check(ptr, len) -> r {
                r := 0
                // First 2 bytes must be "0x" (0x30 0x78)
                if and(eq(len, 42), eq(and(shr(240, calldataload(ptr)), 0xffff), 0x3078)) {
                    // Validate 40 hex chars: 0-9 (0x30-0x39) or a-f (0x61-0x66)
                    let end := add(ptr, 42)
                    for { let p := add(ptr, 2) } lt(p, end) { p := add(p, 1) } {
                        let c := byte(0, calldataload(p))
                        if iszero(
                            or(
                                and(gt(c, 0x2f), lt(c, 0x3a)), // 0-9
                                and(gt(c, 0x60), lt(c, 0x67)) // a-f
                            )
                        ) {
                            leave
                        }
                    }
                    r := 1
                }
            }
            result := check(label.offset, label.length)
        }
    }
}

