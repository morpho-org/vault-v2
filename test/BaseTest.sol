// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IVaultV2Factory} from "../src/interfaces/IVaultV2Factory.sol";
import {Action, IVaultV2} from "../src/interfaces/IVaultV2.sol";

import {VaultV2Factory} from "../src/VaultV2Factory.sol";
import {VaultV2} from "../src/VaultV2.sol";
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
    IVaultV2Factory vaultFactory;
    IVaultV2 vault;
    IRM irm;

    bytes[] bundle;

    function setUp() public virtual {
        vm.label(address(this), "testContract");

        underlyingToken = new ERC20Mock("UnderlyingToken", "UND");
        vm.label(address(underlyingToken), "underlying");

        allocator = new ManagedAllocator(manager);
        vm.label(address(allocator), "allocator");

        vaultFactory = IVaultV2Factory(address(new VaultV2Factory(address(this))));

        vault = IVaultV2(
            vaultFactory.createVaultV2(
                owner, curator, address(allocator), address(underlyingToken), "VaultToken", "VAULT"
            )
        );
        vm.label(address(vault), "vault");
        irm = new IRM(manager, vault);
        vm.label(address(irm), "IRM");
        vm.prank(curator);
        vault.setIRM(Action.Submit, address(irm));
        vm.prank(curator);
        vault.setIRM(Action.Accept, address(irm));
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
