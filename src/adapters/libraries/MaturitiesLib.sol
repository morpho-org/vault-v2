// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library MaturitiesLib {
    /// @dev Align maturity to the next hour.
    function align(uint256 _maturity) internal pure returns (uint256) {
        uint256 h = 1 hours;
        return (_maturity + h - 1) / h * h;
    }

    /// @dev Index of the bitmap containing the already aligned maturity.
    function bitmapIndex(uint256 alignedMaturity) internal pure returns (uint256) {
        return alignedMaturity / (256 * 1 hours);
    }

    /// @dev Earliest maturity in the bitmap at index.
    /// @dev Always aligned to an hour.
    function maturity(uint256 index) internal pure returns (uint256) {
        return index * 256 * 1 hours;
    }

    /// @dev Least significant set bit. Assumes `bitmap` is not zero.
    function lsb(uint256 bitmap) internal pure returns (uint256 res) {
        assembly {
            res := sub(255, clz(and(bitmap, sub(0, bitmap))))
        }
    }
}
