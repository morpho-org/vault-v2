// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../../lib/midnight/src/libraries/IdLib.sol";
import {VaultV2CompatibleEnterGate} from "../../src/periphery/gates/VaultV2CompatibleEnterGate.sol";
import {VaultV2CompatibleEnterGateFactory} from "../../src/periphery/gates/VaultV2CompatibleEnterGateFactory.sol";
import {
    IVaultV2CompatibleEnterGateFactory
} from "../../src/periphery/gates/interfaces/IVaultV2CompatibleEnterGateFactory.sol";
import {IEnterGateFactory} from "../../src/periphery/gates/interfaces/IEnterGateFactory.sol";

contract VaultV2CompatibleEnterGateFactoryTest is Test {
    VaultV2CompatibleEnterGateFactory internal factory;
    address internal midnight = makeAddr("midnight");
    Market internal market;
    address internal gate = makeAddr("gate");
    address internal adapterFactory = makeAddr("adapterFactory");

    function setUp() public {
        factory = new VaultV2CompatibleEnterGateFactory();
        market.midnight = midnight;
    }

    function testCreateVaultV2CompatibleEnterGate(address caller, address forwardedGate) public {
        vm.recordLogs();
        vm.prank(caller);
        address created = factory.createVaultV2CompatibleEnterGate(forwardedGate, market, bytes32(0));

        assertEq(factory.vaultV2CompatibleEnterGate(forwardedGate, IdLib.toId(market), bytes32(0)), created);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(factory));
        assertEq(logs[0].topics[0], keccak256("CreateVaultV2CompatibleEnterGate(address,address,bytes32)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(created))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(forwardedGate))));
        Market memory expectedMarket = market;
        expectedMarket.enterGate = created;
        assertEq(logs[0].data, abi.encode(IdLib.toId(expectedMarket)));
        assertTrue(IEnterGateFactory(address(factory)).isCreated(created, IdLib.toId(expectedMarket)));
        assertEq(VaultV2CompatibleEnterGate(created).marketId(), IdLib.toId(expectedMarket));
        assertEq(VaultV2CompatibleEnterGate(created).subGate(), forwardedGate);
        assertFalse(VaultV2CompatibleEnterGate(created).canAdmit(adapterFactory));
    }

    function testCreateMultipleGatesWithDifferentSalts() public {
        address first = factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));
        address second = factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(uint256(1)));

        assertNotEq(first, second);
        assertEq(factory.vaultV2CompatibleEnterGate(gate, IdLib.toId(market), bytes32(0)), first);
        assertEq(factory.vaultV2CompatibleEnterGate(gate, IdLib.toId(market), bytes32(uint256(1))), second);
        assertEq(factory.vaultV2CompatibleEnterGate(gate, IdLib.toId(market), bytes32(uint256(2))), address(0));
        assertFalse(factory.isCreated(first, VaultV2CompatibleEnterGate(second).marketId()));
        assertFalse(factory.isCreated(second, VaultV2CompatibleEnterGate(first).marketId()));
        assertTrue(factory.isCreated(first, VaultV2CompatibleEnterGate(first).marketId()));
        assertTrue(factory.isCreated(second, VaultV2CompatibleEnterGate(second).marketId()));
    }

    function testIsCreatedRejectsUnregisteredGates() public {
        address direct = address(new VaultV2CompatibleEnterGate(gate, market));
        VaultV2CompatibleEnterGateFactory otherFactory = new VaultV2CompatibleEnterGateFactory();
        address other = otherFactory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));

        assertFalse(factory.isCreated(address(0), IdLib.toId(market)));
        assertFalse(factory.isCreated(gate, IdLib.toId(market)));
        assertFalse(factory.isCreated(direct, VaultV2CompatibleEnterGate(direct).marketId()));
        assertFalse(factory.isCreated(other, VaultV2CompatibleEnterGate(other).marketId()));
        assertTrue(otherFactory.isCreated(other, VaultV2CompatibleEnterGate(other).marketId()));
    }

    function testMultipleMarkets() public {
        address first = factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));
        market.maturity++;
        address second = factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));

        assertTrue(factory.isCreated(first, VaultV2CompatibleEnterGate(first).marketId()));
        assertTrue(factory.isCreated(second, VaultV2CompatibleEnterGate(second).marketId()));
        assertNotEq(VaultV2CompatibleEnterGate(first).marketId(), VaultV2CompatibleEnterGate(second).marketId());
    }

    function testCreateRevertsWithEnterGate(address otherGate) public {
        vm.assume(otherGate != address(0));
        market.enterGate = otherGate;
        vm.expectRevert(IVaultV2CompatibleEnterGateFactory.NonZeroEnterGate.selector);
        factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));
    }
}
