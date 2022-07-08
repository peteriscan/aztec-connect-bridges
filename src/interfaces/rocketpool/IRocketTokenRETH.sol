// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRocketTokenRETH is IERC20 {
    function getEthValue(uint256 _rethAmount) external view returns (uint256);
    function getRethValue(uint256 _ethAmount) external view returns (uint256);
    function burn(uint256 _rethAmount) external;
}
