// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IMidnightAdapterFactory} from "../../src/adapters/midnight/interfaces/IMidnightAdapterFactory.sol";
import {MidnightRegistry} from "../../src/periphery/registries/MidnightRegistry.sol";
import {IMidnightRegistry} from "../../src/periphery/registries/interfaces/IMidnightRegistry.sol";

contract MidnightRegistryTest is Test {
    IMidnightRegistry registry;
    address midnightAdapterFactory = address(0x1001);

    function setUp() public {
        registry = new MidnightRegistry(midnightAdapterFactory);
    }

    function testConstructor() public view {
        assertEq(registry.midnightAdapterFactory(), midnightAdapterFactory);
    }

    function testIsInRegistry(address adapter, bool isCreated) public {
        vm.assume(adapter != address(vm));
        vm.mockCall(
            midnightAdapterFactory, abi.encodeCall(IMidnightAdapterFactory.isCreated, (adapter)), abi.encode(isCreated)
        );

        assertEq(registry.isInRegistry(adapter), isCreated);
    }
}
