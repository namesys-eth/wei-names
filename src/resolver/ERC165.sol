// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// NOTE: This file is currently unused. Resolver.sol implements supportsInterface inline.
// Kept for potential future use with dynamic interface registration.

import {Config} from "../registry/Config.sol";
import {IERC165, IResolver} from "../interface/Interface.sol";

abstract contract ERC165 is Config {
    mapping(bytes4 selector => bool supported) internal _supportsInterface;

    event InterfaceUpdated(bytes4 indexed interfaceId, address indexed by, bool supported);

    constructor() {
        _supportsInterface[type(IERC165).interfaceId] = true;
        _supportsInterface[IResolver.resolve.selector] = true;
        _supportsInterface[bytes4(keccak256("owner()"))] = true;
    }

    function updateInterface(bytes4 interfaceId, bool supported) external onlyOwner {
        _supportsInterface[interfaceId] = supported;
        emit InterfaceUpdated(interfaceId, msg.sender, supported);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return _supportsInterface[interfaceId];
    }
}
