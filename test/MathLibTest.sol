// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

contract MathLibTest is Test {
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

    /// forge-config: default.allow_internal_expect_revert = true
    function testZeroFloorAddInt(uint256 x, int256 y) public {
        if (y < 0) {
            assertEq(MathLib.zeroFloorAddInt(x, y), x < abs(y) ? 0 : x - abs(y), "down");
        } else {
            uint256 z;
            unchecked {
                z = x + uint256(y);
            }
            if (z < x) {
                vm.expectRevert();
                MathLib.zeroFloorAddInt(x, y);
            } else {
                assertEq(z, MathLib.zeroFloorAddInt(x, y), "up");
            }
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testZeroFloorSubInt(uint256 x, int256 y) public {
        if (x > uint256(type(int256).max)) {
            vm.expectRevert(ErrorsLib.CastOverflow.selector);
            MathLib.zeroFloorSubInt(x, y);
        } else if (y < 0 && int256(x) > type(int256).max + y) {
            vm.expectRevert(stdError.arithmeticError);
            MathLib.zeroFloorSubInt(x, y);
        } else {
            assertEq(MathLib.zeroFloorSubInt(x, y), int256(x) >= y ? uint256(int256(x) - y) : 0);
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testToUint192(uint256 x) public {
        if (x > type(uint192).max) {
            vm.expectRevert(ErrorsLib.CastOverflow.selector);
            MathLib.toUint192(x);
        } else {
            assertEq(MathLib.toUint192(x), uint192(x));
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testToUint128(uint256 x) public {
        if (x > type(uint128).max) {
            vm.expectRevert(ErrorsLib.CastOverflow.selector);
            MathLib.toUint128(x);
        } else {
            assertEq(MathLib.toUint128(x), uint128(x));
        }
    }

    /* INTERNAL FUNCTIONS */

    /// From solady
    /// @dev Returns the absolute value of `x`.
    function abs(int256 x) internal pure returns (uint256 z) {
        unchecked {
            z = (uint256(x) + uint256(x >> 255)) ^ uint256(x >> 255);
        }
    }
}
