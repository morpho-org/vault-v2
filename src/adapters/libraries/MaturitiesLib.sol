// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library MaturitiesLib {
    /// @dev Align maturity to the next hour.
    function align(uint256 _maturity) internal pure returns (uint256) {
        uint256 h = 1 hours;
        return (_maturity + h - 1) / h * h;
    }

    /// @dev Bitmap group containing the already aligned maturity.
    function group(uint256 alignedMaturity) internal pure returns (uint256) {
        return alignedMaturity / (256 * 1 hours);
    }

    /// @dev Starting maturity of a bitmap group.
    /// @dev Always aligned to an hour.
    function maturity(uint256 _group) internal pure returns (uint256) {
        return _group * 256 * 1 hours;
    }

    /// @dev Least significant set bit. Assumes `bitmap` is not zero.
    function lsb(uint256 bitmap) internal pure returns (uint256 res) {
        assembly {
            res := sub(255, clz(and(bitmap, sub(0, bitmap))))
        }
    }
}
