// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IERC173 Contract Ownership Standard
/// @dev See https://eips.ethereum.org/EIPS/eip-173
interface IERC173 {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function owner() external view returns (address owner_);

    function transferOwnership(address newOwner) external;
}
