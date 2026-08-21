// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

uint256 constant MAX_DURATIONS = 8;

library DurationsLib {
    error IndexOutOfBounds();
    error IncorrectDuration();
    error ValueOutOfBounds();

    function get(bytes32 durations, uint256 index) internal pure returns (uint256) {
        require(index < MAX_DURATIONS, IndexOutOfBounds());
        unchecked {
            return uint32(uint256(durations >> (32 * index)));
        }
    }

    function pack(uint256[] memory durations) internal pure returns (bytes32) {
        require(durations.length <= MAX_DURATIONS, IndexOutOfBounds());
        unchecked {
            bytes32 packedDurations;
            uint256 currentDuration;
            for (uint256 i = 0; i < durations.length; i++) {
                uint256 duration = durations[i];
                require(duration > currentDuration, IncorrectDuration());
                require(duration <= type(uint32).max, ValueOutOfBounds());

                currentDuration = duration;
                packedDurations |= bytes32(duration << (32 * i));
            }

            return packedDurations;
        }
    }
}
