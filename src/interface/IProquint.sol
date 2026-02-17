// SPDX-License-Identifier: WTFPL.ETH
pragma solidity ^0.8.30;

/// @title IProquint
/// @notice Full interface for ProquintNFT: ERC721 + commit-reveal registration + inbox + registry.
interface IProquint {
    // ============ Errors ============
    error ZeroOwner();
    error ZeroTo();
    error TransferToZeroAddress();
    error UnsafeRecipient();
    error InvalidTokenId();
    error TokenNotMinted();
    error AlreadyRegistered();
    error CommitmentNotFound();
    error CommitmentTooNew();
    error CommitmentTooOld();
    error InsufficientFee();
    error Expired();
    error NotInPremiumPeriod();
    error NotOwner();
    error InvalidYears();
    error BadOraclePrice();
    error RefundFailed();
    error InInbox();
    error NotInInbox();
    error TooManyInbox();

    // ============ Events ============
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Committed(bytes32 indexed commitment, address indexed committer);
    event Extended(bytes4 indexed id, uint64 newExpiry);
    event Pending(address indexed receiver, bytes4 indexed id, uint64 inboxExpiry);
    event InboxAccepted(address indexed receiver, bytes4 indexed id);
    event InboxRejected(address indexed receiver, bytes4 indexed id, uint256 refund);
    event InboxBurned(bytes4 indexed id, address indexed by, uint256 reward);

    // ============ ERC173 ============
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;

    // ============ ERC721 ============
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function balanceOf(address user) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data)
        external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    // ============ Commit-Reveal ============
    function makeCommitment(bytes32 input, address recipient) external pure returns (bytes32);
    function commit(bytes32 commitment) external;
    function register(bytes32 input) external payable returns (uint256 tokenId);
    function registerTo(bytes32 input, address to) external payable returns (uint256 tokenId);
    function registerPremium(bytes32 input) external payable returns (uint256 tokenId);
    function renew(bytes32 input) external payable;

    // ============ Inbox ============
    function inboxCount(address user) external view returns (uint8);
    function inboxExpiry(bytes4 id) external view returns (uint64);
    function totalInbox() external view returns (uint256);
    function acceptInbox(bytes4 id) external;
    function rejectInbox(bytes4 id) external;
    function burnExpiredInbox(bytes4 id) external;

    // ============ Registry ============
    function owner(bytes32 node) external view returns (address);
    function recordExists(bytes32 node) external view returns (bool);
    function owner(bytes4 id) external view returns (address);
    function recordExists(bytes4 id) external view returns (bool);
    function isProquint(bytes32 node) external view returns (bool);
    function primaryName(address user) external view returns (bytes32);
    function commitments(bytes32) external view returns (uint256);
    function expiresAt(bytes4) external view returns (uint64);
    function getNode(bytes4 id) external pure returns (bytes32);
    function getExpiry(bytes4 id) external view returns (uint64);
    function isAvailable(bytes4 id) external view returns (bool);
    function isExpired(bytes4 id) external view returns (bool);
    function isInPremiumPeriod(bytes4 id) external view returns (bool);
    function totalSupply() external view returns (uint256);

    // ============ Admin ============
    function withdraw() external;
}
