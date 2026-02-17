// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IWNS
/// @notice Full interface for NameNFT: ERC721 + commit-reveal registration + .wei name system.
interface IWNS {
    // ============ Errors ============
    error Expired();
    error TooDeep();
    error EmptyLabel();
    error InvalidName();
    error InvalidLength();
    error LengthMismatch();
    error NotParentOwner();
    error PremiumTooHigh();
    error InsufficientFee();
    error AlreadyCommitted();
    error CommitmentTooNew();
    error CommitmentTooOld();
    error AlreadyRegistered();
    error CommitmentNotFound();
    error DecayPeriodTooLong();

    // ============ Events ============
    event NameRegistered(
        uint256 indexed tokenId, string label, address indexed owner, uint256 expiresAt
    );
    event SubdomainRegistered(uint256 indexed tokenId, uint256 indexed parentId, string label);
    event NameRenewed(uint256 indexed tokenId, uint256 newExpiresAt);
    event PrimaryNameSet(address indexed addr, uint256 indexed tokenId);
    event Committed(bytes32 indexed commitment, address indexed committer);
    event AddrChanged(bytes32 indexed node, address addr);
    event ContenthashChanged(bytes32 indexed node, bytes contenthash);
    event AddressChanged(bytes32 indexed node, uint256 coinType, bytes addr);
    event TextChanged(bytes32 indexed node, string indexed key, string value);
    event DefaultFeeChanged(uint256 fee);
    event LengthFeeChanged(uint256 indexed length, uint256 fee);
    event LengthFeeCleared(uint256 indexed length);
    event PremiumSettingsChanged(uint256 maxPremium, uint256 decayPeriod);

    // ============ Structs ============
    struct NameRecord {
        string label;
        uint256 parent;
        uint64 expiresAt;
        uint64 epoch;
        uint64 parentEpoch;
    }

    // ============ Constants ============
    function WEI_NODE() external view returns (bytes32);

    // ============ ERC721 ============
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
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
    function makeCommitment(string calldata label, address owner, bytes32 secret)
        external
        pure
        returns (bytes32);
    function commit(bytes32 commitment) external;
    function reveal(string calldata label, bytes32 secret)
        external
        payable
        returns (uint256 tokenId);

    // ============ Subdomains ============
    function registerSubdomain(string calldata label, uint256 parentId) external returns (uint256);
    function registerSubdomainFor(string calldata label, uint256 parentId, address to)
        external
        returns (uint256);

    // ============ Renewal ============
    function renew(uint256 tokenId) external payable;
    function isExpired(uint256 tokenId) external view returns (bool);
    function inGracePeriod(uint256 tokenId) external view returns (bool);
    function expiresAt(uint256 tokenId) external view returns (uint256);

    // ============ Resolution ============
    function setAddr(uint256 tokenId, address addr) external;
    function setPrimaryName(uint256 tokenId) external;
    function resolve(uint256 tokenId) external view returns (address);
    function reverseResolve(address addr) external view returns (string memory);

    // ============ ENS-Compatible Resolver (tokenId) ============
    function setContenthash(uint256 tokenId, bytes calldata hash) external;
    function contenthash(uint256 tokenId) external view returns (bytes memory);
    function setAddrForCoin(uint256 tokenId, uint256 coinType, bytes calldata addr) external;
    function addr(uint256 tokenId, uint256 coinType) external view returns (bytes memory);
    function setText(uint256 tokenId, string calldata key, string calldata value) external;
    function text(uint256 tokenId, string calldata key) external view returns (string memory);

    // ============ ENS-Compatible Resolver (bytes32 node) ============
    function addr(bytes32 node) external view returns (address);
    function addr(bytes32 node, uint256 coinType) external view returns (bytes memory);
    function text(bytes32 node, string calldata key) external view returns (string memory);
    function contenthash(bytes32 node) external view returns (bytes memory);

    // ============ Storage Getters ============
    function defaultFee() external view returns (uint256);
    function maxPremium() external view returns (uint256);
    function premiumDecayPeriod() external view returns (uint256);
    function lengthFees(uint256 length) external view returns (uint256);
    function lengthFeeSet(uint256 length) external view returns (bool);
    function records(uint256 tokenId) external view returns (NameRecord memory);
    function recordVersion(uint256 tokenId) external view returns (uint256);
    function commitments(bytes32 commitment) external view returns (uint256);
    function primaryName(address owner) external view returns (uint256);

    // ============ Lookups ============
    function computeId(string calldata fullName) external pure returns (uint256);
    function computeNamehash(string calldata fullName) external pure returns (bytes32);
    function isAvailable(string calldata label, uint256 parentId) external view returns (bool);
    function getFullName(uint256 tokenId) external view returns (string memory);
    function normalize(string calldata label) external pure returns (string memory);
    function isAsciiLabel(string calldata label) external pure returns (bool);

    // ============ Fees ============
    function getFee(uint256 length) external view returns (uint256);
    function getPremium(uint256 tokenId) external view returns (uint256);

    // ============ Admin ============
    function setDefaultFee(uint256 fee) external;
    function setLengthFees(uint256[] calldata lengths, uint256[] calldata fees) external;
    function clearLengthFee(uint256 length) external;
    function setPremiumSettings(uint256 _maxPremium, uint256 _decayPeriod) external;
    function withdraw() external;
}
