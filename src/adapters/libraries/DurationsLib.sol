// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library DurationsLib {
    /// @dev Assumes index < 8. Otherwise the return value is unspecified.
    function get(bytes32 durations, uint256 index) internal pure returns (uint256) {
        unchecked {
            // forge-lint: disable-next-item(unsafe-typecast) durations fit in 32 bits.
            return uint32(uint256(durations >> (32 * index)));
        }
    }

    /// @dev Assumes length <= 8.
    function unpack(bytes32 packedDurations, uint256 length) internal pure returns (uint256[] memory) {
        uint256[] memory durations = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            durations[i] = get(packedDurations, i);
        }
        return durations;
    }

    /// @dev Assumes durations.length <= 8 and that each duration fits in 32 bits.
    function pack(uint256[] memory durations) internal pure returns (bytes32) {
        bytes32 packedDurations;
        for (uint256 i = 0; i < durations.length; i++) {
            packedDurations |= bytes32(durations[i] << (32 * i));
        }
        return packedDurations;
    }
}
