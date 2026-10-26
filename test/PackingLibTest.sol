// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {PackingLib} from "../src/adapters/libraries/PackingLib.sol";

contract PackingLibTest is Test {
    uint256 internal constant MAX_LENGTH = 8;

    using PackingLib for bytes32;
    using PackingLib for uint256[];

    function testPackAndGet(uint256 length) public pure {
        length = bound(length, 0, MAX_LENGTH);
        uint256[] memory durations = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            durations[i] = i + 1;
        }

        bytes32 packedDurations = durations.pack();
        for (uint256 i = 0; i < MAX_LENGTH; i++) {
            assertEq(packedDurations.get(i), i < length ? i + 1 : 0);
        }
    }

    function testPackAndUnpack(uint256 length) public pure {
        length = bound(length, 0, MAX_LENGTH);
        uint256[] memory durations = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            durations[i] = i + 1;
        }

        assertEq(durations.pack().unpack(length), durations);
    }
}
