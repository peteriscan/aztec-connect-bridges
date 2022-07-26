// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

interface IRocketDepositPool {
    function getBalance() external view returns (uint256);
    function deposit() external payable;
}
