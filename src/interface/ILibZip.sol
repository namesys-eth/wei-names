// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ILibZip {
    function flzCompress(bytes memory data) external pure returns (bytes memory result);
    function flzDecompress(bytes memory data) external pure returns (bytes memory result);
    function cdCompress(bytes memory data) external pure returns (bytes memory result);
    function cdDecompress(bytes memory data) external pure returns (bytes memory result);
}
