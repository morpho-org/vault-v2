// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

contract MathTest is Test {
    function setUp() public {}

    function testMulDivDown(uint256 x, uint256 y, uint256 d) public pure {
        vm.assume(d != 0);
        // Proof that it's the tightest bound when y != 0:
        // x * y <= max <=> x <= max / y <=> x <= ⌊max / y⌋
        if (y != 0) x = bound(x, 0, type(uint256).max / y);
        assertEq(MathLib.mulDivDown(x, y, d), (x * y) / d);
    }

    function testMulDivUp(uint256 x, uint256 y, uint256 d) public pure {
        vm.assume(d != 0);
        // Proof that it's the tightest bound when y != 0:
        // x * y + d <= max <=> x <= (max - d) / y <=> x <= ⌊(max - d) / y⌋
        if (y != 0) x = bound(x, 0, (type(uint256).max - d) / y);
        assertEq(MathLib.mulDivUp(x, y, d), (x * y + d - 1) / d);
    }

    function testZeroFloorSub(uint256 x, uint256 y) public pure {
        assertEq(MathLib.zeroFloorSub(x, y), x < y ? 0 : x - y);
    }

    function testMin(uint256 x, uint256 y) public pure {
        assertEq(MathLib.min(x, y), x < y ? x : y);
    }
}
