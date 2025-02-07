// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {VaultsV2} from "../src/VaultsV2.sol";
import {IRM} from "../src/IRM.sol";
import {ManagedAllocator} from "../src/allocators/ManagedAllocator.sol";
import {EncodeLib} from "../src/libraries/EncodeLib.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";

contract BaseTest is Test {
    address immutable manager = makeAddr("manager");
    address immutable owner = makeAddr("owner");
    address immutable curator = makeAddr("curator");

    ERC20Mock underlyingToken;
    ManagedAllocator allocator;
    VaultsV2 vault;
    IRM irm;

    bytes[] bundle;

    function setUp() public virtual {
        underlyingToken = new ERC20Mock("UnderlyingToken", "UND");

        allocator = new ManagedAllocator(manager);

        vault = new VaultsV2(owner, curator, address(allocator), address(underlyingToken), "VaultToken", "VAULT");

        irm = new IRM(manager, vault);
        vm.prank(curator);
        vault.setIRM(address(irm));
    }

    function testConstructor() public view {
        assertEq(vault.owner(), owner);
        assertEq(address(vault.asset()), address(underlyingToken));
        assertEq(address(vault.curator()), curator);
        assertEq(address(vault.allocator()), address(allocator));
        assertEq(address(vault.irm()), address(irm));
        assertEq(allocator.owner(), manager);
        assertEq(irm.owner(), manager);
        assertEq(address(irm.vault()), address(vault));
    }
}
