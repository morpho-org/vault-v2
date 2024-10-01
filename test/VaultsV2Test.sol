// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {VaultsV2} from "../src/VaultsV2.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";

contract VaultsV2Test is Test {
    VaultsV2 public vault;
    address immutable guardian = makeAddr("guardian");
    address immutable initialOwner = makeAddr("initial owner");

    function setUp() public {
        address underlying = address(new ERC20Mock("UnderlyingToken", "UND"));

        vm.prank(initialOwner);
        vault = new VaultsV2(guardian, underlying, "VaultToken", "VAULT");
    }

    function testConstructor() public view {
        assertEq(vault.owner(), initialOwner);
        assertEq(vault.guardian(), guardian);
    }
}
