// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {VaultsV2} from "../src/VaultsV2.sol";

contract VaultsV2Test is Test {
    VaultsV2 public vault;

    function setUp() public {
        vault = new VaultsV2();
    }

    function testConstructor() public view {
        assertEq(address(vault).balance, 0);
    }
}
