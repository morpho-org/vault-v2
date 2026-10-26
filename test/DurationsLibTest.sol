// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {DurationsLib, MAX_DURATIONS} from "../src/adapters/libraries/DurationsLib.sol";

contract DurationsLibTest is Test {
    using DurationsLib for bytes32;
    using DurationsLib for uint256[];

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

    function testPackAndUnpack(uint256 length) public pure {
        length = bound(length, 0, MAX_DURATIONS);
        uint256[] memory durations = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            durations[i] = i + 1;
        }

        assertEq(durations.pack().unpack(length), durations);
    }
}
