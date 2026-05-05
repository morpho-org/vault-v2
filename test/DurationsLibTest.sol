// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {DurationsLib, MAX_DURATIONS} from "../src/adapters/libraries/DurationsLib.sol";

contract DurationsLibTest is Test {
    using DurationsLib for bytes32;

    /// forge-config: default.allow_internal_expect_revert = true
    function testGetInvalidIndex(bytes32 durations, uint256 index) public {
        index = bound(index, MAX_DURATIONS, type(uint256).max);
        vm.expectRevert(DurationsLib.IndexOutOfBounds.selector);
        durations.get(index);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSetInvalidIndex(bytes32 durations, uint256 index, uint32 value) public {
        index = bound(index, MAX_DURATIONS, type(uint256).max);
        vm.expectRevert(DurationsLib.IndexOutOfBounds.selector);
        durations.set(index, value);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSetInvalidValue(bytes32 durations, uint256 index, uint256 value) public {
        index = bound(index, 0, MAX_DURATIONS - 1);
        value = bound(value, uint256(type(uint32).max) + 1, type(uint256).max);
        vm.expectRevert(DurationsLib.ValueOutOfBounds.selector);
        durations.set(index, value);
    }

    function testGetAndSet(bytes32 durations, uint32 value, uint256 index) public pure {
        index = bound(index, 0, MAX_DURATIONS - 1);
        bytes32 newDurations = durations.set(index, value);
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            if (i == index) {
                assertEq(newDurations.get(i), value, "set");
            } else {
                assertEq(newDurations.get(i), durations.get(i), "not set");
            }
        }
    }

    function testLayout(bytes32 durations, uint32 value) public pure {
        assertEq(uint32(uint256(durations.set(0, value))), value, "first");
        assertEq(uint32(bytes4(durations.set(7, value))), value, "last");
    }
}
