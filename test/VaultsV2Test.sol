// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {VaultsV2} from "../src/VaultsV2.sol";
import {IRM} from "../src/IRM.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";

contract VaultsV2Test is Test {
    address immutable guardian = makeAddr("guardian");
    address immutable initialCurator = makeAddr("initial curator");
    VaultsV2 vault;
    address initialIRM;

    function setUp() public {
        address underlying = address(new ERC20Mock("UnderlyingToken", "UND"));

        vm.startPrank(initialCurator);
        vault = new VaultsV2(guardian, underlying, "VaultToken", "VAULT");
        initialIRM = address(new IRM(vault));
        vault.setIRM(initialIRM);
        vm.stopPrank();
    }

    function testConstructor() public view {
        assertEq(vault.curator(), initialCurator);
        assertEq(vault.guardian(), guardian);
        assertEq(address(vault.irm()), initialIRM);
    }
}
