// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// Optimize: packing.
struct TimelockData {
    uint256 validAt; // Can be shrunk to 64 bits.
    uint256 value; // Can be shrunk to 160 bits.
    uint256 index; // Can be shrunk to 8 bits.
}

// Optimize: packing.
struct TimelockConfig {
    bool canIncrease;
    bool canDecrease;
    uint256 duration; // Can be shrunk to 64 bits.
}

interface IMarket {
    function asset() external view returns (IERC20);
    function totalAssets() external view returns (uint256);
    function deposit(uint256, address) external returns (uint256);
    function withdraw(uint256, address, address) external returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function maxWithdraw(address) external view returns (uint256);
}

interface IVaultV2 is IMarket {
    function markets(uint256) external view returns (IMarket);
    function marketsLength() external view returns (uint256);
    // Use trick to make a nice interface returning `TimelockData memory`.
    function timelockData(bytes4) external view returns (uint256, uint256, uint256);
    function timelockConfig(bytes4) external view returns (bool, bool, uint256);
}
