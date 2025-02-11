// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

uint256 constant WAD = 1e18;

// TODO: complete this interface. Should it be IERC4626 ?
interface IMarket {
    function totalAssets() external view returns (uint256);
    function deposit(uint256, address) external returns (uint256);
    function withdraw(uint256, address, address) external returns (uint256);
    function convertToAssets(uint256) external returns (uint256);
    function convertToShares(uint256) external returns (uint256);
    function balanceOf(address) external returns (uint256);
}
