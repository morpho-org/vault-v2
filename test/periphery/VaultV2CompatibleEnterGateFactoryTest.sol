// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../../lib/midnight/src/libraries/IdLib.sol";
import {VaultV2CompatibleEnterGate} from "../../src/periphery/gates/VaultV2CompatibleEnterGate.sol";
import {VaultV2CompatibleEnterGateFactory} from "../../src/periphery/gates/VaultV2CompatibleEnterGateFactory.sol";
import {IEnterGateFactory} from "../../lib/midnight/src/interfaces/IEnterGateFactory.sol";

contract VaultV2CompatibleEnterGateFactoryTest is Test {
    VaultV2CompatibleEnterGateFactory internal factory;
    address internal midnight = makeAddr("midnight");
    Market internal market;
    address internal gate = makeAddr("gate");
    address internal adapterFactory = makeAddr("adapterFactory");

    function setUp() public {
        factory = new VaultV2CompatibleEnterGateFactory(adapterFactory);
        market.midnight = midnight;
    }

    function testCreateVaultV2CompatibleEnterGate(address caller, address forwardedGate) public {
        vm.recordLogs();
        vm.prank(caller);
        address created = factory.createVaultV2CompatibleEnterGate(forwardedGate, market, bytes32(0));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, created);
        assertEq(logs[0].topics[0], keccak256("AddAdmitterFactory(address)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(adapterFactory))));
        assertEq(logs[1].emitter, address(factory));
        assertEq(logs[1].topics[0], keccak256("CreateVaultV2CompatibleEnterGate(address,address,bytes32)"));
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(created))));
        assertEq(logs[1].topics[2], bytes32(uint256(uint160(forwardedGate))));
        Market memory expectedMarket = market;
        expectedMarket.enterGate = created;
        assertEq(logs[1].data, abi.encode(IdLib.toId(expectedMarket)));
        assertTrue(IEnterGateFactory(address(factory)).isGate(created, IdLib.toId(expectedMarket)));
        assertEq(VaultV2CompatibleEnterGate(created).midnight(), midnight);
        assertEq(VaultV2CompatibleEnterGate(created).marketId(), IdLib.toId(expectedMarket));
        assertEq(VaultV2CompatibleEnterGate(created).subGate(), forwardedGate);
        assertEq(factory.initialAdapterFactory(), adapterFactory);
        assertTrue(VaultV2CompatibleEnterGate(created).canAdmit(adapterFactory));
    }

    function testCreateMultipleGatesWithDifferentSalts() public {
        address first = factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));
        address second = factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(uint256(1)));

        assertNotEq(first, second);
        assertFalse(factory.isGate(first, VaultV2CompatibleEnterGate(second).marketId()));
        assertFalse(factory.isGate(second, VaultV2CompatibleEnterGate(first).marketId()));
        assertTrue(factory.isGate(first, VaultV2CompatibleEnterGate(first).marketId()));
        assertTrue(factory.isGate(second, VaultV2CompatibleEnterGate(second).marketId()));
    }

    function testIsGateRejectsUnregisteredGates() public {
        address direct = address(new VaultV2CompatibleEnterGate(gate, market, adapterFactory));
        VaultV2CompatibleEnterGateFactory otherFactory = new VaultV2CompatibleEnterGateFactory(adapterFactory);
        address other = otherFactory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));

        assertFalse(factory.isGate(address(0), IdLib.toId(market)));
        assertFalse(factory.isGate(gate, IdLib.toId(market)));
        assertFalse(factory.isGate(direct, VaultV2CompatibleEnterGate(direct).marketId()));
        assertFalse(factory.isGate(other, VaultV2CompatibleEnterGate(other).marketId()));
        assertTrue(otherFactory.isGate(other, VaultV2CompatibleEnterGate(other).marketId()));
    }

    function testMultipleMarkets() public {
        address first = factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));
        market.maturity++;
        address second = factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));

        assertTrue(factory.isGate(first, VaultV2CompatibleEnterGate(first).marketId()));
        assertTrue(factory.isGate(second, VaultV2CompatibleEnterGate(second).marketId()));
        assertNotEq(VaultV2CompatibleEnterGate(first).marketId(), VaultV2CompatibleEnterGate(second).marketId());
    }

    function testCreateRevertsWithEnterGate(address otherGate) public {
        vm.assume(otherGate != address(0));
        market.enterGate = otherGate;
        vm.expectRevert(VaultV2CompatibleEnterGateFactory.NonZeroEnterGate.selector);
        factory.createVaultV2CompatibleEnterGate(gate, market, bytes32(0));
    }
}
