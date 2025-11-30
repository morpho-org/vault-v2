// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

bytes32 constant M0 = 0xFFFFFFFF00000000000000000000000000000000000000000000000000000000;
bytes32 constant M1 = 0x00000000FFFFFFFF000000000000000000000000000000000000000000000000;
bytes32 constant M2 = 0x0000000000000000FFFFFFFF0000000000000000000000000000000000000000;
bytes32 constant M3 = 0x000000000000000000000000FFFFFFFF00000000000000000000000000000000;
bytes32 constant M4 = 0x00000000000000000000000000000000FFFFFFFF000000000000000000000000;
bytes32 constant M5 = 0x0000000000000000000000000000000000000000FFFFFFFF0000000000000000;
bytes32 constant M6 = 0x000000000000000000000000000000000000000000000000FFFFFFFF00000000;
bytes32 constant M7 = 0x00000000000000000000000000000000000000000000000000000000FFFFFFFF;

uint256 constant MAX_DURATIONS = 8;

library DurationsLib {
    error OutOfBounds();

    function count(bytes32 duration) internal pure returns (uint256 len) {
        assembly {
            len := add(len, gt(and(duration, M0), 0))
            len := add(len, gt(and(duration, M1), 0))
            len := add(len, gt(and(duration, M2), 0))
            len := add(len, gt(and(duration, M3), 0))
            len := add(len, gt(and(duration, M4), 0))
            len := add(len, gt(and(duration, M5), 0))
            len := add(len, gt(and(duration, M6), 0))
            len := add(len, gt(and(duration, M7), 0))
        }
    }

    function get(bytes32 durations, uint256 index) internal pure returns (uint256) {
        require(index < MAX_DURATIONS, OutOfBounds());
        unchecked {
            return uint256((durations >> (32 * (7 - index))) & M7);
        }
    }

    function set(bytes32 durations, uint256 index, uint256 value) internal pure returns (bytes32) {
        require(index < MAX_DURATIONS, OutOfBounds());
        unchecked {
            return durations & ~(M0 >> (32 * index)) | bytes32(uint256(uint32(value)) << (32 * (7 - index)));
        }
    }
}
