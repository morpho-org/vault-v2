// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {VaultV2CompatibleEnterGate} from "../../src/adapters/midnight/gates/VaultV2CompatibleEnterGate.sol";
import {
    VaultV2CompatibleEnterGateFactory
} from "../../src/adapters/midnight/gates/VaultV2CompatibleEnterGateFactory.sol";
import {IEnterGateFactory} from "../../src/adapters/midnight/gates/interfaces/IEnterGateFactory.sol";

contract VaultV2CompatibleEnterGateFactoryTest is Test {
    VaultV2CompatibleEnterGateFactory internal factory;
    address internal gate = makeAddr("gate");
    address internal adapterFactory = makeAddr("adapterFactory");

    function setUp() public {
        factory = new VaultV2CompatibleEnterGateFactory();
    }

    function testCreateVaultV2CompatibleEnterGate(address caller, address forwardedGate, bool enabled) public {
        bytes32 preSalt = bytes32(0);
        bytes32 salt = keccak256(abi.encode(preSalt, caller));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(VaultV2CompatibleEnterGate).creationCode, abi.encode(forwardedGate, enabled))
        );
        address expected = vm.computeCreate2Address(salt, initCodeHash, address(factory));
        vm.recordLogs();
        vm.prank(caller);
        address created = factory.createVaultV2CompatibleEnterGate(forwardedGate, enabled, preSalt);

        assertEq(created, expected);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(factory));
        assertEq(logs[0].topics[0], keccak256("CreateVaultV2CompatibleEnterGate(address,address,address,bool,bytes32)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(caller))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(created))));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(forwardedGate))));
        assertEq(logs[0].data.length, 64);
        (bool emittedEnabled, bytes32 emittedPreSalt) = abi.decode(logs[0].data, (bool, bytes32));
        assertEq(emittedEnabled, enabled);
        assertEq(emittedPreSalt, preSalt);
        assertEq(VaultV2CompatibleEnterGate(created).admitEnabled(), enabled);
        assertTrue(IEnterGateFactory(address(factory)).isCreated(created));
        assertEq(VaultV2CompatibleEnterGate(created).subGate(), forwardedGate);
        assertFalse(VaultV2CompatibleEnterGate(created).canAdmit(adapterFactory));
    }

    function testCreateMultipleGatesWithDifferentSalts() public {
        bytes32 firstPreSalt = bytes32(0);
        bytes32 secondPreSalt = bytes32(uint256(1));
        address first = factory.createVaultV2CompatibleEnterGate(gate, true, firstPreSalt);
        address second = factory.createVaultV2CompatibleEnterGate(gate, true, secondPreSalt);

        assertNotEq(first, second);
        assertTrue(factory.isCreated(first));
        assertTrue(factory.isCreated(second));
    }

    function testSamePreSaltFromDifferentCallersCreatesDifferentGates() public {
        bytes32 preSalt = bytes32(0);
        address first = factory.createVaultV2CompatibleEnterGate(gate, true, preSalt);

        address otherCaller = makeAddr("other");
        vm.prank(otherCaller);
        address second = factory.createVaultV2CompatibleEnterGate(gate, true, preSalt);

        assertNotEq(first, second);
        assertTrue(factory.isCreated(first));
        assertTrue(factory.isCreated(second));
    }

    function testIsCreatedRejectsUnregisteredGates() public {
        address direct = address(new VaultV2CompatibleEnterGate(gate, true));
        VaultV2CompatibleEnterGateFactory otherFactory = new VaultV2CompatibleEnterGateFactory();
        address other = otherFactory.createVaultV2CompatibleEnterGate(gate, true, bytes32(0));

        assertFalse(factory.isCreated(address(0)));
        assertFalse(factory.isCreated(gate));
        assertFalse(factory.isCreated(direct));
        assertFalse(factory.isCreated(other));
        assertTrue(otherFactory.isCreated(other));
    }
}
