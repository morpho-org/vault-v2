// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IAaveV3AToken
/// @notice Minimal Aave V3 aToken interface
interface IAaveV3AToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
