// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MathLib} from "../../libraries/MathLib.sol";

library SharesLib {
    using MathLib for uint256;

    /// @dev Virtual shares provide precision for ownership conversions.
    uint256 internal constant VIRTUAL_SHARES = 1e9;
    /// @dev Virtual assets provide precision for ownership conversions.
    uint256 internal constant VIRTUAL_ASSETS = 1;

    /// @dev Calculates the value of `assets` quoted in shares, rounding down.
    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivDown(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @dev Calculates the value of `assets` quoted in shares, rounding up.
    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivUp(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @dev Calculates the value of `shares` quoted in assets, rounding down.
    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivDown(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }
}
