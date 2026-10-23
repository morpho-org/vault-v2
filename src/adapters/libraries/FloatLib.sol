// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library FloatLib {
    /// @dev Returns the largest float48 <= x.
    function toFloatDown(uint256 x) internal pure returns (uint48) {
        uint256 e = exponent(x);
        // forge-lint: disable-next-item(unsafe-typecast) The encoded mantissa and exponent fit in 48 bits.
        return uint48((x >> e) << 8 | e);
    }

    /// @dev Returns the smallest float48 >= x.
    function toFloatUp(uint256 x) internal pure returns (uint48) {
        uint256 e = exponent(x);
        uint256 m = x >> e;
        if ((x & ((uint256(1) << e) - 1)) != 0) m++;
        if (m == 1 << 40) {
            m >>= 1;
            e++;
        }
        // forge-lint: disable-next-item(unsafe-typecast) The encoded mantissa and exponent fit in 48 bits.
        return uint48((m << 8) | e);
    }

    function toUint256(uint48 f) internal pure returns (uint256) {
        return uint256(f >> 8) << (f & 0xff);
    }

    function exponent(uint256 x) internal pure returns (uint256) {
        uint256 bitLength;
        if (x >> 128 != 0) {
            x >>= 128;
            bitLength += 128;
        }
        if (x >> 64 != 0) {
            x >>= 64;
            bitLength += 64;
        }
        if (x >> 32 != 0) {
            x >>= 32;
            bitLength += 32;
        }
        if (x >> 16 != 0) {
            x >>= 16;
            bitLength += 16;
        }
        if (x >> 8 != 0) {
            x >>= 8;
            bitLength += 8;
        }
        if (x >> 4 != 0) {
            x >>= 4;
            bitLength += 4;
        }
        if (x >> 2 != 0) {
            x >>= 2;
            bitLength += 2;
        }
        if (x >> 1 != 0) bitLength++;
        bitLength += x > 0 ? 1 : 0;
        return bitLength > 40 ? bitLength - 40 : 0;
    }
}
