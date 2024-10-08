// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {VaultsV2} from "../src/VaultsV2.sol";
import {IRM} from "../src/IRM.sol";
import {CustodialCurator} from "../src/curators/CustodialCurator.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";

contract VaultsV2Test is Test {
    address immutable guardian = makeAddr("guardian");
    address immutable interestManager = makeAddr("interest manager");
    CustodialCurator curator;
    ERC20Mock underlyingToken;
    VaultsV2 vault;
    // IRM initialIRM;

    // bytes[] bundle;

    function setUp() public {
        underlyingToken = new ERC20Mock("UnderlyingToken", "UND");
        curator = new CustodialCurator();

        vault = new VaultsV2(address(curator), guardian, address(underlyingToken), "VaultToken", "VAULT");
        // initialIRM = new IRM(interestManager, vault);

        // Should make a bundle instead:
        // vault.setIRM(address(initialIRM));
    }

    function testConstructor() public view {
        assertEq(vault.guardian(), guardian);
        assertEq(address(vault.curator()), address(curator));
        // assertEq(address(vault.irm()), address(initialIRM));
        assertEq(address(vault.asset()), address(underlyingToken));
    }
}
