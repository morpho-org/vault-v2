// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {VaultsV2} from "../src/VaultsV2.sol";
import {IRM} from "../src/IRM.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";

contract VaultsV2Test is Test {
    address immutable guardian = makeAddr("guardian");
    address immutable initialCurator = makeAddr("initial curator");
    ERC20Mock underlyingToken;
    VaultsV2 vault;
    IRM initialIRM;

    function setUp() public {
        underlyingToken = new ERC20Mock("UnderlyingToken", "UND");

        vm.startPrank(initialCurator);
        vault = new VaultsV2(guardian, address(underlyingToken), "VaultToken", "VAULT");
        initialIRM = new IRM(vault);
        vault.setIRM(address(initialIRM));
        vm.stopPrank();
    }

    function testConstructor() public view {
        assertEq(vault.guardian(), guardian);
        assertEq(vault.curator(), initialCurator);
        assertEq(address(vault.irm()), address(initialIRM));
        assertEq(address(vault.asset()), address(underlyingToken));
    }
}
