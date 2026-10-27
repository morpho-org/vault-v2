// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VaultV2CompatibleEnterGate} from "../../src/periphery/gates/VaultV2CompatibleEnterGate.sol";
import {VaultV2CompatibleEnterGateFactory} from "../../src/periphery/gates/VaultV2CompatibleEnterGateFactory.sol";
import {IEnterGateFactory} from "../../src/periphery/gates/interfaces/IEnterGateFactory.sol";

contract VaultV2CompatibleEnterGateFactoryTest is Test {
    VaultV2CompatibleEnterGateFactory internal factory;
    address internal midnight = makeAddr("midnight");
    address internal gate = makeAddr("gate");
    address internal adapterFactory = makeAddr("adapterFactory");

    function setUp() public {
        factory = new VaultV2CompatibleEnterGateFactory();
    }

    function testCreateVaultV2CompatibleEnterGate(address caller, address forwardedGate) public {
        vm.recordLogs();
        vm.prank(caller);
        address created = factory.createVaultV2CompatibleEnterGate(forwardedGate, address(midnight), bytes32(0));

        assertEq(factory.vaultV2CompatibleEnterGate(forwardedGate, address(midnight), bytes32(0)), created);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(factory));
        assertEq(logs[0].topics[0], keccak256("CreateVaultV2CompatibleEnterGate(address,address,address)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(created))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(forwardedGate))));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(midnight))));
        assertEq(logs[0].data.length, 0);
        assertEq(VaultV2CompatibleEnterGate(created).midnight(), midnight);
        assertTrue(IEnterGateFactory(address(factory)).isCreated(created));
        assertEq(VaultV2CompatibleEnterGate(created).subGate(), forwardedGate);
        assertFalse(VaultV2CompatibleEnterGate(created).canAdmit(adapterFactory));
    }

    function testCreateMultipleGatesWithDifferentSalts() public {
        address first = factory.createVaultV2CompatibleEnterGate(gate, address(midnight), bytes32(0));
        address second = factory.createVaultV2CompatibleEnterGate(gate, address(midnight), bytes32(uint256(1)));

        assertNotEq(first, second);
        assertEq(factory.vaultV2CompatibleEnterGate(gate, address(midnight), bytes32(0)), first);
        assertEq(factory.vaultV2CompatibleEnterGate(gate, address(midnight), bytes32(uint256(1))), second);
        assertEq(factory.vaultV2CompatibleEnterGate(gate, address(midnight), bytes32(uint256(2))), address(0));
        assertTrue(factory.isCreated(first));
        assertTrue(factory.isCreated(second));
    }

    function testCreateMultipleGatesWithDifferentMidnights() public {
        address otherMidnight = makeAddr("otherMidnight");
        address first = factory.createVaultV2CompatibleEnterGate(gate, midnight, bytes32(0));
        address second = factory.createVaultV2CompatibleEnterGate(gate, otherMidnight, bytes32(0));
        assertNotEq(first, second);
        assertEq(factory.vaultV2CompatibleEnterGate(gate, midnight, bytes32(0)), first);
        assertEq(factory.vaultV2CompatibleEnterGate(gate, otherMidnight, bytes32(0)), second);
    }

    function testIsCreatedRejectsUnregisteredGates() public {
        address direct = address(new VaultV2CompatibleEnterGate(gate, address(midnight)));
        VaultV2CompatibleEnterGateFactory otherFactory = new VaultV2CompatibleEnterGateFactory();
        address other = otherFactory.createVaultV2CompatibleEnterGate(gate, address(midnight), bytes32(0));

        assertFalse(factory.isCreated(address(0)));
        assertFalse(factory.isCreated(gate));
        assertFalse(factory.isCreated(direct));
        assertFalse(factory.isCreated(other));
        assertTrue(otherFactory.isCreated(other));
    }
}
