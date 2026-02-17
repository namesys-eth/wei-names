// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Auth} from "../registry/Auth.sol";

/**
 * @title RedirectResolver
 * @notice Key-specific and wildcard redirects. A redirect points (node, key) to
 *         another node's records. Key-specific takes precedence over wildcard.
 *         Destination must explicitly allow the source via enableRedirect().
 */
abstract contract RedirectResolver is Auth {
    uint256 internal constant WILDCARD = type(uint256).max;
    bytes32 internal constant WILDCARD_KEY = bytes32(type(uint256).max);

    error NotEnabled();

    event RedirectSet(
        bytes32 indexed node, bytes32 indexed key, bytes32 indexed target, address operator
    );
    /// @param expiry 0 = disable; type(uint256).max = forever; else allow until block.timestamp < expiry.
    event RedirectEnabled(
        bytes32 indexed destination,
        bytes32 indexed source,
        bytes32 key,
        uint256 expiry,
        address operator
    );

    function _timeOk(uint256 t) private view returns (bool) {
        return t != 0 && (t == WILDCARD || block.timestamp < t);
    }

    /// @dev Check if destination allows source to redirect for this key.
    /// Cascade: source+key → source+WILDCARD → WILDCARD+key → WILDCARD+WILDCARD.
    function _redirectOk(bytes32 destination, bytes32 source, bytes32 key)
        internal
        view
        returns (bool)
    {
        mapping(bytes32 => mapping(bytes32 => uint256)) storage ra = _nodes[destination].redirectAllowlist;
        if (_timeOk(ra[source][key])) return true;
        if (_timeOk(ra[source][WILDCARD_KEY])) return true;
        if (_timeOk(ra[WILDCARD_KEY][key])) return true;
        return _timeOk(ra[WILDCARD_KEY][WILDCARD_KEY]);
    }

    /// @notice Set redirect for (node,key). Actual selector check happens at resolve time.
    function setRedirect(bytes32 node, bytes32 key, bytes32 target, uint256 ver) external {
        require(_isAuthorized(node), Unauthorized());
        _nodes[node].entries[key].redirect.target = target;
        _nodes[node].entries[key].redirect.version = ver;
        emit RedirectSet(node, key, target, msg.sender);
    }

    function setWildcardRedirect(bytes32 node, bytes32 target, uint256 ver) external {
        require(_isAuthorized(node), Unauthorized());
        _nodes[node].entries[WILDCARD_KEY].redirect.target = target;
        _nodes[node].entries[WILDCARD_KEY].redirect.version = ver;
        emit RedirectSet(node, WILDCARD_KEY, target, msg.sender);
    }

    /// @notice Enable redirect from source for specific key (or WILDCARD_KEY for all).
    /// @param key keccak(request) for specific record, or WILDCARD_KEY for all.
    /// @param expiry 0 = disable; type(uint256).max = forever; else allow until block.timestamp < expiry.
    function enableRedirect(bytes32 destination, bytes32 source, bytes32 key, uint256 expiry)
        external
    {
        require(_isAuthorized(destination), Unauthorized());
        _nodes[destination].redirectAllowlist[source][key] = expiry;
        emit RedirectEnabled(destination, source, key, expiry, msg.sender);
    }

    /// @notice Get redirect target for (node, key). Falls back to wildcard.
    function getRedirect(bytes32 node, bytes32 key)
        public
        view
        returns (bytes32 target, uint256 ver)
    {
        Entry storage e = _nodes[node].entries[key];
        target = e.redirect.target;
        if (target != bytes32(0)) return (target, e.redirect.version);
        e = _nodes[node].entries[WILDCARD_KEY];
        return (e.redirect.target, e.redirect.version);
    }

    function isRedirectEnabled(bytes32 destination, bytes32 source, bytes32 key)
        public
        view
        returns (bool)
    {
        return _redirectOk(destination, source, key);
    }

    /// @dev Resolve redirect for (node,key). Returns target node (or original node if none/disabled).
    function _resolveRedirect(bytes32 node, bytes32 key)
        internal
        view
        returns (bytes32 target, uint256 ver)
    {
        (target, ver) = getRedirect(node, key);
        if (target == bytes32(0)) return (node, 0);
        if (!_redirectOk(target, node, key)) return (node, 0);
        return (target, ver);
    }
}

