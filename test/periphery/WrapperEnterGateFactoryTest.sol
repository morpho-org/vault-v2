// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IMidnightAdapter} from "../../src/adapters/interfaces/IMidnightAdapter.sol";
import {WrapperEnterGate} from "../../src/periphery/gates/WrapperEnterGate.sol";
import {WrapperEnterGateFactory} from "../../src/periphery/gates/WrapperEnterGateFactory.sol";
import {IEnterGateFactory} from "../../src/periphery/gates/interfaces/IEnterGateFactory.sol";

contract WrapperEnterGateFactoryTest is Test {
    WrapperEnterGateFactory internal factory;
    address internal adapter = makeAddr("adapter");
    address internal vault = makeAddr("vault");
    address internal gate = makeAddr("gate");

    function setUp() public {
        factory = new WrapperEnterGateFactory();
        vm.mockCall(adapter, abi.encodeCall(IMidnightAdapter.parentVault, ()), abi.encode(vault));
    }

    function testCreateWrapperEnterGate(address caller, address forwardedGate) public {
        vm.recordLogs();
        vm.prank(caller);
        address created = factory.createWrapperEnterGate(adapter, forwardedGate);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(factory));
        assertEq(logs[0].topics[0], keccak256("CreateWrapperEnterGate(address,address,address)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(adapter))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(created))));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(forwardedGate))));
        assertEq(logs[0].data, bytes(""));
        assertTrue(IEnterGateFactory(address(factory)).isGate(created));
        assertEq(WrapperEnterGate(created).adapter(), adapter);
        assertEq(WrapperEnterGate(created).vault(), vault);
        assertEq(WrapperEnterGate(created).gate(), forwardedGate);
    }

    function testCreateMultipleIdenticalGates() public {
        address first = factory.createWrapperEnterGate(adapter, gate);
        address second = factory.createWrapperEnterGate(adapter, gate);

        assertNotEq(first, second);
        assertTrue(factory.isGate(first));
        assertTrue(factory.isGate(second));
    }

    function testIsGateRejectsUnregisteredGates() public {
        address direct = address(new WrapperEnterGate(adapter, vault, gate));
        WrapperEnterGateFactory otherFactory = new WrapperEnterGateFactory();
        address other = otherFactory.createWrapperEnterGate(adapter, gate);

        assertFalse(factory.isGate(address(0)));
        assertFalse(factory.isGate(adapter));
        assertFalse(factory.isGate(gate));
        assertFalse(factory.isGate(direct));
        assertFalse(factory.isGate(other));
        assertTrue(otherFactory.isGate(other));
    }

    function testMultipleVaults() public {
        address otherAdapter = makeAddr("otherAdapter");
        address otherVault = makeAddr("otherVault");
        vm.mockCall(otherAdapter, abi.encodeCall(IMidnightAdapter.parentVault, ()), abi.encode(otherVault));

        address first = factory.createWrapperEnterGate(adapter, gate);
        address second = factory.createWrapperEnterGate(otherAdapter, gate);

        assertTrue(factory.isGate(first));
        assertTrue(factory.isGate(second));
        assertEq(WrapperEnterGate(first).vault(), vault);
        assertEq(WrapperEnterGate(second).vault(), otherVault);
        assertEq(WrapperEnterGate(second).adapter(), otherAdapter);
    }

    function testCreateBubblesAdapterRevert() public {
        vm.mockCallRevert(adapter, abi.encodeCall(IMidnightAdapter.parentVault, ()), "adapter reverted");

        vm.expectRevert(bytes("adapter reverted"));
        factory.createWrapperEnterGate(adapter, gate);
    }
}
