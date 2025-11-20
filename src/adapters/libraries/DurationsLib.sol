// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

uint256 constant MAX_DURATIONS = 8;

library DurationsLib {
    /* ERRORS */

    error InvalidValue();
    error InvalidIndex();

    /* FUNCTIONS */

    function array(bytes32 durations) internal pure returns (uint256[] memory) {}

    function get(bytes32 durations, uint256 index) internal pure returns (uint256 duration) {
        require(index < MAX_DURATIONS, InvalidIndex());
        assembly {
            let shift := sub(224, mul(32, index))
            duration := and(shr(shift, durations), 0xffffffff)
        }
    }

    function set(bytes32 durations, uint256 index, uint256 value) internal pure returns (bytes32 newDurations) {
        require(value <= type(uint32).max, InvalidValue());
        require(index < MAX_DURATIONS, InvalidIndex());
        assembly {
            let shift := sub(224, mul(32, index))
            let masked := and(durations, not(shl(shift, 0xffffffff)))
            newDurations := or(masked, shl(shift, value))
        }
    }
}
