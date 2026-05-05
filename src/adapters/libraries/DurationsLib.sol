// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

uint256 constant MAX_DURATIONS = 8;

library DurationsLib {
    error IndexOutOfBounds();
    error ValueOutOfBounds();

    function get(bytes32 durations, uint256 index) internal pure returns (uint256) {
        require(index < MAX_DURATIONS, IndexOutOfBounds());
        unchecked {
            return uint32(uint256(durations >> (32 * index)));
        }
    }

    function set(bytes32 durations, uint256 index, uint256 value) internal pure returns (bytes32) {
        require(index < MAX_DURATIONS, IndexOutOfBounds());
        require(value <= type(uint32).max, ValueOutOfBounds());
        unchecked {
            uint256 s = 32 * index;
            /// forge-lint: disable-next-line(incorrect-shift)
            return bytes32((uint256(durations) & ~(0xFFFFFFFF << s)) | (value << s));
        }
    }
}
