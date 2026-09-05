// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {DurationsLib, MAX_DURATIONS} from "../src/adapters/libraries/DurationsLib.sol";

contract DurationsLibTest is Test {
    using DurationsLib for bytes32;
    using DurationsLib for uint256[];

    /// forge-config: default.allow_internal_expect_revert = true
    function testGetInvalidIndex(bytes32 durations, uint256 index) public {
        index = bound(index, MAX_DURATIONS, type(uint256).max);
        vm.expectRevert(DurationsLib.IndexOutOfBounds.selector);
        durations.get(index);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testPackInvalidLength() public {
        uint256[] memory durations = new uint256[](MAX_DURATIONS + 1);
        vm.expectRevert(DurationsLib.IndexOutOfBounds.selector);
        durations.pack();
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testPackInvalidValue(uint256 value) public {
        value = bound(value, uint256(type(uint32).max) + 1, type(uint256).max);
        uint256[] memory durations = new uint256[](1);
        durations[0] = value;

        vm.expectRevert(DurationsLib.ValueOutOfBounds.selector);
        durations.pack();
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testPackZeroDuration() public {
        uint256[] memory durations = new uint256[](1);

        vm.expectRevert(DurationsLib.IncorrectDuration.selector);
        durations.pack();
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testPackNonIncreasing(uint32 first, uint32 second) public {
        first = uint32(bound(first, 1, type(uint32).max));
        second = uint32(bound(second, 0, first));

        uint256[] memory durations = new uint256[](2);
        durations[0] = first;
        durations[1] = second;

        vm.expectRevert(DurationsLib.IncorrectDuration.selector);
        durations.pack();
    }

    function testPackAndGet(uint256 length) public pure {
        length = bound(length, 0, MAX_DURATIONS);
        uint256[] memory durations = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            durations[i] = i + 1;
        }

        bytes32 packedDurations = durations.pack();
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            assertEq(packedDurations.get(i), i < length ? i + 1 : 0);
        }
    }
}
