// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

interface IRocketStorage {
    function getAddress(bytes32 key) external view returns (address);
}
