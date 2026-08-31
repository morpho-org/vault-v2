// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {RegistryList} from "../../src/periphery/registries/RegistryList.sol";
import {IRegistryList} from "../../src/periphery/registries/interfaces/IRegistryList.sol";

contract RegistryListTest is Test {
    IRegistryList registry;
    address user = address(0x1);

    function setUp() public {
        registry = IRegistryList(address(new RegistryList()));
    }

    function testConstructor() public view {
        assertEq(registry.owner(), address(this));
        assertEq(registry.subRegistriesLength(), 0);
    }

    function testConstructorEvent() public {
        vm.expectEmit(true, false, false, false);
        emit RegistryList.Constructor(address(this));
        new RegistryList();
    }

    function testSetOwner(address newOwner) public {
        vm.expectEmit(true, false, false, false);
        emit RegistryList.SetOwner(newOwner);

        registry.setOwner(newOwner);
        assertEq(registry.owner(), newOwner);
    }

    function testSetOwnerOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        registry.setOwner(address(0x123));
    }

    function testAddSubRegistry(address subRegistry) public {
        vm.expectEmit(true, false, false, false);
        emit RegistryList.AddSubRegistry(subRegistry);

        registry.addSubRegistry(subRegistry);

        assertEq(registry.subRegistriesLength(), 1);
        assertEq(registry.subRegistries(0), subRegistry);
    }

    function testAddRegistrySubRegistryOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        registry.addSubRegistry(address(0x1002));
    }

    function testIsInRegistryWithSubRegistries(address adapter, bool subRegistry1Result, bool subRegistry2Result)
        public
    {
        address subRegistry1 = address(0x1001);
        address subRegistry2 = address(0x1002);

        registry.addSubRegistry(subRegistry1);
        registry.addSubRegistry(subRegistry2);

        vm.mockCall(
            subRegistry1, abi.encodeWithSignature("isInRegistry(address)", adapter), abi.encode(subRegistry1Result)
        );
        vm.mockCall(
            subRegistry2, abi.encodeWithSignature("isInRegistry(address)", adapter), abi.encode(subRegistry2Result)
        );

        bool expected = subRegistry1Result || subRegistry2Result;
        assertEq(registry.isInRegistry(adapter), expected);
    }

    function testIsInRegistryNoSubRegistries(address adapter) public view {
        assertFalse(registry.isInRegistry(adapter));
    }

    function testAddingRevertingSubRegistry(address adapter, address legitSubRegistry, address revertingSubRegistry)
        public
    {
        assumeAddressIsNot(legitSubRegistry, AddressType.ForgeAddress);
        vm.assume(legitSubRegistry != revertingSubRegistry);
        vm.assume(legitSubRegistry != address(0));

        registry.addSubRegistry(legitSubRegistry);
        registry.addSubRegistry(revertingSubRegistry);

        vm.mockCall(legitSubRegistry, abi.encodeWithSignature("isInRegistry(address)", adapter), abi.encode(true));

        assertTrue(registry.isInRegistry(adapter));
    }
}
