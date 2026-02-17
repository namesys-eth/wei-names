// SPDX-License-Identifier: WTFPL.ETH
pragma solidity ^0.8.30;

import {LibBytes} from "solady/utils/LibBytes.sol";
import {LibString} from "solady/utils/LibString.sol";

/**
 * @title Utils
 * @notice Utility library for off-chain URL building and selector-to-JSON mapping.
 */
library Utils {
    using LibBytes for bytes;

    /**
     * @dev Build off-chain gateway URLs for CCIP-Read.
     * @param domain  Dot-separated domain (e.g. "sub.name.wei").
     * @param path    Slash-separated reverse path (e.g. "wei/name/sub").
     * @param file    JSON filename from selectorToJson (e.g. "addr/eth.json").
     * @param ch      Contenthash bytes (IPFS/IPNS multicodec prefix + raw hash).
     * @param hostSuffix  ".limo" for ENS, "" for WNS.
     * @param gateways    IPFS/IPNS gateway hostnames.
     */
    function buildOffchainUrls(
        string memory domain,
        string memory path,
        string memory file,
        bytes memory ch,
        string memory hostSuffix,
        string[] memory gateways
    ) internal pure returns (string[] memory urls) {
        bool hasDomain = bytes(domain).length != 0;
        bool hasPath = bytes(path).length != 0;
        string memory host = hasDomain ? string.concat(domain, hostSuffix) : "";
        string memory route = hasPath ? string.concat(path, "/", file) : file;
        string memory primary =
            hasDomain ? string.concat("https://", host, "/.well-known/", route) : "";

        if (ch.length == 0) {
            urls = new string[](hasDomain ? 1 : 0);
            if (hasDomain) urls[0] = primary;
            return urls;
        }

        bool isIpns = (ch.length > 2 && ch[0] == bytes1(0xe5) && ch[1] == bytes1(0x01));
        bool isIpfs = (ch.length > 2 && ch[0] == bytes1(0xe3) && ch[1] == bytes1(0x01));
        if (!isIpfs && !isIpns) {
            urls = new string[](hasDomain ? 1 : 0);
            if (hasDomain) urls[0] = primary;
            return urls;
        }
        string memory proto = isIpns ? "ipns" : "ipfs";
        bytes memory raw = LibBytes.slice(ch, 2, ch.length);
        string memory ipfsPath =
            string.concat("/", proto, "/f", LibString.toHexStringNoPrefix(raw), "/", route);
        uint256 n = gateways.length;
        bool hasLink = hasDomain && bytes(hostSuffix).length > 0;
        urls = new string[](n + (hasDomain ? 1 : 0) + (hasLink ? 1 : 0));
        uint256 idx = 0;
        if (hasDomain) urls[idx++] = primary;
        if (hasLink) urls[idx++] = string.concat("https://", domain, ".link/.well-known/", route);
        for (uint256 i = 0; i < n; i++) {
            urls[idx++] = string.concat("https://", gateways[i], ipfsPath);
        }
    }

    /**
     * @dev Map a resolver function selector to its JSON file path for off-chain lookup.
     *      e.g. addr(bytes32) => "addr/eth.json", text(bytes32,string) => "/text/{key}.json".
     */
    function selectorToJson(bytes calldata request) internal pure returns (string memory file) {
        bytes4 sel = bytes4(request[:4]);
        if (sel == bytes4(keccak256("addr(bytes32)"))) {
            return "addr/eth.json";
        }
        if (sel == bytes4(keccak256("addr(bytes32,uint256)"))) {
            if (request.length >= 68) {
                (, uint256 chainId) = abi.decode(request[4:], (bytes32, uint256));
                if (chainId == 1 || chainId == 0) return "addr/eth.json";
                return string.concat("addr/", LibString.toString(chainId), ".json");
            }
            return "addr/eth.json";
        }
        if (sel == bytes4(keccak256("contenthash(bytes32)"))) {
            return "contenthash.json";
        }
        if (sel == bytes4(keccak256("text(bytes32,string)"))) {
            (, string memory key) = abi.decode(request[4:], (bytes32, string));
            return string.concat("/text/", key, ".json");
        }
        if (sel == bytes4(keccak256("name(bytes32)"))) {
            return "name.json";
        }
        return "record.json";
    }
}
