// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

uint256 constant WAD = 1e18;

// TODO: also inherit from IERC4626
interface IVaultsV2 {
    function totalAssets() external view returns (uint256);
}
