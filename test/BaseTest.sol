// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {VaultsV2} from "../src/VaultsV2.sol";
import {IRM} from "../src/IRM.sol";
import {CustodialCurator} from "../src/curators/CustodialCurator.sol";
import {EncodeLib} from "../src/libraries/EncodeLib.sol";

import {VaultsV2Mock} from "./mocks/VaultsV2Mock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";

contract BaseTest is Test {
    address immutable manager = makeAddr("manager");
    address immutable guardian = makeAddr("guardian");

    ERC20Mock underlyingToken;
    CustodialCurator curator;
    VaultsV2 vault;
    IRM irm;

    bytes[] bundle;

    function setUp() public {
        underlyingToken = new ERC20Mock("UnderlyingToken", "UND");

        curator = new CustodialCurator(manager);

        vault = VaultsV2(
            address(new VaultsV2Mock(address(curator), guardian, address(underlyingToken), "VaultToken", "VAULT"))
        );

        irm = new IRM(manager, vault);
        bytes[] memory setIRMBundle = new bytes[](1);
        setIRMBundle[0] = EncodeLib.setIRMCall(address(irm));
        vm.prank(manager);
        vault.multiCall(setIRMBundle);
    }

    function testConstructor() public view {
        assertEq(vault.guardian(), guardian);
        assertEq(address(vault.asset()), address(underlyingToken));
        assertEq(address(vault.curator()), address(curator));
        assertEq(address(vault.irm()), address(irm));
        assertEq(curator.owner(), manager);
        assertEq(irm.owner(), manager);
        assertEq(address(irm.vault()), address(vault));
    }
}
