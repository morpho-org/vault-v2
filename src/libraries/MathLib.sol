// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {ErrorsLib} from "./ErrorsLib.sol";

library MathLib {
    /// @dev Returns (x * y) / d rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @dev Returns (x * y) / d rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    /// @dev Returns max(0, x - y).
    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    /// @dev Casts from uint256 to uint128, reverting if input number is too large.
    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, ErrorsLib.CastOverflow());
        return uint128(x);
    }

    /// @dev Casts from int256 to uint256, reverting if input number is negative.
    function toUint256(int256 x) internal pure returns (uint256) {
        require(x >= 0, ErrorsLib.CastOverflow());
        return uint256(x);
    }

    /// @dev Returns min(x, y).
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }
}
