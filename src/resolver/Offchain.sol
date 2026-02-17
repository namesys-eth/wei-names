// SPDX-License-Identifier: WTFPL.ETH
pragma solidity ^0.8.30;

import {Auth} from "../registry/Auth.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {LibProquint} from "@proquint/LibProquint.sol";

/**
 * @title OffchainResolver
 * @notice CCIP2-style off-chain record storage (EIP-3668 / CCIP-Read).
 *         Uses EIP-712 typed structured data for approval and record signatures.
 *         Stores recordhash per node, manages gateways, and verifies
 *         off-chain signatures in the __callback.
 */
abstract contract OffchainResolver is Auth, EIP712 {
    string[] internal _gateways;

    /* ── Events ──────────────────────────────────────────────────────── */

    event RecordhashUpdated(address indexed owner, bytes32 indexed node, bytes contenthash);
    event GatewayAdded(string indexed domain);
    event GatewayRemoved(uint256 indexed index, string domain);
    event GatewaySet(uint256 indexed index, string domain);

    /* ── Errors ──────────────────────────────────────────────────────── */

    error NoGateways();
    error GatewayIndex();
    error InvalidSignature(string reason);
    error OffchainRequestFailed(string reason);

    /* ── Constants ───────────────────────────────────────────────────── */

    bytes4 private constant RH_SEL = bytes4(keccak256("recordhash(bytes32)"));

    /**
     * @dev EIP-712 typehash for off-chain record.
     *      OffchainRecord(bytes32 node,uint256 expiry,bytes result)
     *      bytes4(RECORD_TYPEHASH) is the callback selector for signed records.
     */
    bytes32 private constant RECORD_TYPEHASH =
        keccak256("OffchainRecord(bytes32 node,uint256 expiry,bytes result)");

    /**
     * @dev EIP-712 typehash for off-chain signer approval.
     *      ApproveOffchainSigner(bytes32 node,address signer,uint256 expiry)
     *      bytes4(APPROVAL_TYPEHASH) is the callback selector for approved records.
     *      The approver is recovered from the signature.
     */
    bytes32 private constant APPROVAL_TYPEHASH =
        keccak256("ApproveOffchainSigner(bytes32 node,address signer,uint256 expiry)");

    /* ── EIP-712 domain ──────────────────────────────────────────────── */

    /** @dev EIP-712 domain name and version. Override in concrete contract if needed. */
    function _domainNameAndVersion()
        internal
        pure
        virtual
        override
        returns (string memory name, string memory version)
    {
        name = "WNS Resolver";
        version = "1";
    }

    /* ── Recordhash getters/setters ──────────────────────────────────── */

    /** @dev Storage key for recordhash of a node. */
    function _rhKey(bytes32 node) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(RH_SEL, node));
    }

    /** @notice Get recordhash for a node. */
    function getRecordhash(bytes32 node) external view returns (bytes memory) {
        return _getRecordhash(node);
    }

    /** @dev Resolve recordhash for a node (used by resolve). */
    function _getRecordhash(bytes32 node) internal view returns (bytes memory) {
        Record storage rec = _recordAt(node, _rhKey(node));
        uint256 v = rec.latest;
        if (v > 0) return rec.val[v];
        return "";
    }

    /** @dev Write recordhash and emit event. */
    function _setRecordhash(bytes32 node, bytes memory _rh) internal {
        Record storage rec = _recordAt(node, _rhKey(node));
        rec.val[++rec.latest] = _rh;
        emit RecordhashUpdated(msg.sender, node, _rh);
    }

    /** @notice Set recordhash (generic auth). */
    function setRecordhash(bytes32 node, bytes calldata _rh) external {
        require(_isAuthorized(node), Unauthorized());
        _setRecordhash(node, _rh);
    }

    /** @notice Set recordhash for ENS-owned node only. */
    function setENSRecordhash(bytes32 node, bytes calldata _rh) external {
        require(_isAuthorizedENS(node), Unauthorized());
        _setRecordhash(node, _rh);
    }

    /** @notice Set recordhash for WNS-owned node only. */
    function setWNSRecordhash(bytes32 node, bytes calldata _rh) external {
        require(_isAuthorizedWNS(node), Unauthorized());
        _setRecordhash(node, _rh);
    }

    /** @notice Set recordhash for proquint-owned node only. */
    function setProquintRecordhash(bytes4 id, bytes calldata _rh) external {
        bytes32 node = LibProquint.namehash4(id);
        require(_isAuthorizedPRO(node), Unauthorized());
        _setRecordhash(node, _rh);
    }

    /* ── EIP-712 signature verification ──────────────────────────────── */

    /**
     * @dev Recover the signer from an EIP-712 OffchainRecord signature.
     *      Checks expiry. Authority checks are the caller's job.
     * @param recordSig EIP-712 signature over OffchainRecord struct.
     * @param node      The node the record belongs to.
     * @param expiry    Timestamp after which the record expires.
     * @param result    The raw record result bytes.
     * @return signer   The address that produced the signature.
     */
    function _recoverRecordSigner(
        bytes memory recordSig,
        bytes32 node,
        uint256 expiry,
        bytes memory result
    ) internal view returns (address signer) {
        require(expiry >= block.timestamp, InvalidSignature("RECORD_EXPIRED"));
        bytes32 structHash = keccak256(
            abi.encode(RECORD_TYPEHASH, node, expiry, keccak256(result))
        );
        signer = ECDSA.tryRecover(_hashTypedData(structHash), recordSig);
    }

    /**
     * @dev Recover the approver from an EIP-712 ApproveOffchainSigner signature.
     *      Checks expiry. Authority checks are the caller's job.
     * @param signer    Address being approved as off-chain record signer.
     * @param node      The node the approval is for.
     * @param signature EIP-712 signature over ApproveOffchainSigner struct.
     * @param expiry    Timestamp after which the approval expires.
     * @return approver The address that produced the signature.
     */
    function _recoverApproval(
        address signer,
        bytes32 node,
        bytes memory signature,
        uint256 expiry
    ) internal view returns (address approver) {
        require(expiry >= block.timestamp, InvalidSignature("APPROVAL_EXPIRED"));
        bytes32 structHash = keccak256(
            abi.encode(APPROVAL_TYPEHASH, node, signer, expiry)
        );
        approver = ECDSA.tryRecover(_hashTypedData(structHash), signature);
    }

    /* ── CCIP-Read callback ──────────────────────────────────────────── */

    /**
     * @notice CCIP-Read callback: verify checkhash, recover signers from EIP-712 signatures,
     *         and check authority. All signer/approver addresses recovered from signatures.
     *
     * Response types (selector = bytes4 of the EIP-712 typehash):
     *   RECORD_TYPEHASH: (uint256 expiry, bytes recordSig, bytes result)
     *     - Record signer recovered from recordSig, must be owner/on-chain-approved.
     *   APPROVAL_TYPEHASH: (uint256 recordExpiry, uint256 approvalExpiry, bytes approvalSig, bytes recordSig, bytes result)
     *     - Approver recovered from approvalSig, must be owner/on-chain-approved.
     *     - Record signer recovered from recordSig, must match signer in approval struct.
     */
    function __callback(bytes calldata response, bytes calldata extradata)
        external
        view
        returns (bytes memory result)
    {
        bytes4 _type = bytes4(response[:4]);
        (
            bytes32 node,
            uint256 blocknumber,
            bytes32 checkhash,,,
            bytes memory request
        ) = abi.decode(extradata, (bytes32, uint256, bytes32, string, string, bytes));
        address nodeOwner = _ownerForNode(node);
        require(block.number <= blocknumber + 7, OffchainRequestFailed("BLOCK_TIMEOUT"));
        require(
            checkhash
                == keccak256(
                    abi.encodePacked(
                        address(this), blockhash(blocknumber), nodeOwner, request
                    )
                ),
            OffchainRequestFailed("BAD_CHECKSUM")
        );

        if (_type == bytes4(RECORD_TYPEHASH)) {
            uint256 expiry;
            bytes memory recordSig;
            (expiry, recordSig, result) =
                abi.decode(response[4:], (uint256, bytes, bytes));
            address signer = _recoverRecordSigner(recordSig, node, expiry, result);
            require(signer != address(0), InvalidSignature("BAD_SIGNED_RECORD"));
            require(signer == nodeOwner || _approval[nodeOwner][node][signer], Unauthorized());
        } else if (_type == bytes4(APPROVAL_TYPEHASH)) {
            uint256 recordExpiry;
            uint256 approvalExpiry;
            bytes memory approvalSig;
            bytes memory recordSig;
            (recordExpiry, approvalExpiry, approvalSig, recordSig, result) =
                abi.decode(response[4:], (uint256, uint256, bytes, bytes, bytes));
            address signer = _recoverRecordSigner(recordSig, node, recordExpiry, result);
            require(signer != address(0), InvalidSignature("BAD_SIGNED_RECORD"));
            address approver = _recoverApproval(signer, node, approvalSig, approvalExpiry);
            require(approver == nodeOwner || _approval[nodeOwner][node][approver], Unauthorized());
        } else {
            revert OffchainRequestFailed("UNSUPPORTED_TYPE");
        }
    }

    /* ── Gateway management ──────────────────────────────────────────── */

    /** @notice Get all configured IPFS/IPNS gateway hostnames. */
    function getGateways() external view returns (string[] memory) {
        return _gateways;
    }

    /** @notice Add a gateway hostname. Only contract owner. */
    function addGateway(string calldata domain) external onlyOwner {
        _gateways.push(domain);
        emit GatewayAdded(domain);
    }

    /** @notice Remove a gateway by index (swap-and-pop). Only contract owner. */
    function removeGateway(uint256 index) external onlyOwner {
        require(index < _gateways.length, GatewayIndex());
        require(_gateways.length > 1, NoGateways());
        string memory domain = _gateways[index];
        _gateways[index] = _gateways[_gateways.length - 1];
        _gateways.pop();
        emit GatewayRemoved(index, domain);
    }

    /** @notice Replace a gateway at index. Only contract owner. */
    function setGateway(uint256 index, string calldata domain) external onlyOwner {
        require(index < _gateways.length, GatewayIndex());
        _gateways[index] = domain;
        emit GatewaySet(index, domain);
    }
}
