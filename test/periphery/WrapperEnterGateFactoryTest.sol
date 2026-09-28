// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../../lib/midnight/src/libraries/IdLib.sol";
import {WrapperEnterGate} from "../../src/periphery/gates/WrapperEnterGate.sol";
import {WrapperEnterGateFactory} from "../../src/periphery/gates/WrapperEnterGateFactory.sol";
import {IEnterGateFactory} from "../../src/periphery/gates/interfaces/IEnterGateFactory.sol";

contract WrapperEnterGateFactoryTest is Test {
    WrapperEnterGateFactory internal factory;
    address internal midnight = makeAddr("midnight");
    Market internal market;
    address internal gate = makeAddr("gate");

    function setUp() public {
        factory = new WrapperEnterGateFactory();
        market.midnight = midnight;
    }

    function testCreateWrapperEnterGate(address caller, address forwardedGate) public {
        vm.recordLogs();
        vm.prank(caller);
        address created = factory.createWrapperEnterGate(forwardedGate, market);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(factory));
        assertEq(logs[0].topics[0], keccak256("CreateWrapperEnterGate(address,address,bytes32)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(created))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(forwardedGate))));
        Market memory expectedMarket = market;
        expectedMarket.enterGate = created;
        assertEq(logs[0].data, abi.encode(IdLib.toId(expectedMarket)));
        assertTrue(IEnterGateFactory(address(factory)).isGate(created));
        assertEq(WrapperEnterGate(created).midnight(), midnight);
        assertEq(WrapperEnterGate(created).marketId(), IdLib.toId(expectedMarket));
        assertEq(WrapperEnterGate(created).gate(), forwardedGate);
    }

    function testCreateMultipleIdenticalGates() public {
        address first = factory.createWrapperEnterGate(gate, market);
        address second = factory.createWrapperEnterGate(gate, market);

        assertNotEq(first, second);
        assertTrue(factory.isGate(first));
        assertTrue(factory.isGate(second));
    }

    function testIsGateRejectsUnregisteredGates() public {
        address direct = address(new WrapperEnterGate(gate, market));
        WrapperEnterGateFactory otherFactory = new WrapperEnterGateFactory();
        address other = otherFactory.createWrapperEnterGate(gate, market);

        assertFalse(factory.isGate(address(0)));
        assertFalse(factory.isGate(gate));
        assertFalse(factory.isGate(direct));
        assertFalse(factory.isGate(other));
        assertTrue(otherFactory.isGate(other));
    }

    function testMultipleMarkets() public {
        address first = factory.createWrapperEnterGate(gate, market);
        market.maturity++;
        address second = factory.createWrapperEnterGate(gate, market);

        assertTrue(factory.isGate(first));
        assertTrue(factory.isGate(second));
        assertNotEq(WrapperEnterGate(first).marketId(), WrapperEnterGate(second).marketId());
    }

    function testCreateReplacesEnterGate(address otherGate) public {
        market.enterGate = otherGate;
        address created = factory.createWrapperEnterGate(gate, market);
        Market memory expectedMarket = market;
        expectedMarket.enterGate = created;
        assertEq(WrapperEnterGate(created).marketId(), IdLib.toId(expectedMarket));
    }
}
