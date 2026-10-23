// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

uint256 constant MAX_DURATIONS = 8;

library DurationsLib {
    error TooManyDurations();
    error DurationsNotIncreasing();
    error DurationTooHigh();

    /// @dev Assumes index < MAX_DURATIONS. Otherwise the return value is unspecified.
    function get(bytes32 durations, uint256 index) internal pure returns (uint256) {
        unchecked {
            // forge-lint: disable-next-item(unsafe-typecast) durations fit in 32 bits.
            return uint32(uint256(durations >> (32 * index)));
        }
    }

    /// @dev Assumes length <= MAX_DURATIONS.
    function unpack(bytes32 packedDurations, uint256 length) internal pure returns (uint256[] memory) {
        uint256[] memory durations = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            durations[i] = get(packedDurations, i);
        }
        return durations;
    }

    function pack(uint256[] memory durations) internal pure returns (bytes32) {
        require(durations.length <= MAX_DURATIONS, TooManyDurations());
        unchecked {
            bytes32 packedDurations;
            uint256 currentDuration;
            for (uint256 i = 0; i < durations.length; i++) {
                uint256 duration = durations[i];
                require(duration > currentDuration, DurationsNotIncreasing());
                require(duration <= type(uint32).max, DurationTooHigh());

                currentDuration = duration;
                packedDurations |= bytes32(duration << (32 * i));
            }

            return packedDurations;
        }
    }
}
