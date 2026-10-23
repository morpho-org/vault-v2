// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {FloatLib} from "../src/adapters/libraries/FloatLib.sol";

contract FloatLibTest is Test {
    function testToFloatDown(uint128 x) public pure {
        uint256 down = FloatLib.toUint256(FloatLib.toFloatDown(x));
        assertLe(down, x);
        if (x < 1 << 40) assertEq(down, x);
        else assertLt((uint256(x) - down) << 39, x);
    }

    function testToFloatUp(uint128 x) public pure {
        uint256 up = FloatLib.toUint256(FloatLib.toFloatUp(x));
        assertGe(up, x);
        if (x < 1 << 40) assertEq(up, x);
        else assertLt((up - uint256(x)) << 39, x);
    }

    function testToFloatRoundTripExact(uint40 x) public pure {
        assertEq(FloatLib.toUint256(FloatLib.toFloatDown(x)), x);
        assertEq(FloatLib.toUint256(FloatLib.toFloatUp(x)), x);
    }

    function testUint128MaxDoesNotOverflow() public pure {
        assertLe(FloatLib.toUint256(FloatLib.toFloatDown(type(uint128).max)), type(uint128).max);
        assertGe(FloatLib.toUint256(FloatLib.toFloatUp(type(uint128).max)), type(uint128).max);
    }

    function testUint64MaxDoesNotOverflow() public pure {
        assertLe(FloatLib.toUint256(FloatLib.toFloatDown(type(uint64).max)), type(uint64).max);
        assertGe(FloatLib.toUint256(FloatLib.toFloatUp(type(uint64).max)), type(uint64).max);
    }
}
