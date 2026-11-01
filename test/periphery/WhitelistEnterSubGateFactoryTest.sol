// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {WhitelistEnterSubGate} from "../../src/periphery/gates/WhitelistEnterSubGate.sol";
import {WhitelistEnterSubGateFactory} from "../../src/periphery/gates/WhitelistEnterSubGateFactory.sol";
import {IWhitelistEnterSubGateFactory} from "../../src/periphery/gates/interfaces/IWhitelistEnterSubGateFactory.sol";

contract WhitelistEnterSubGateFactoryTest is Test {
    WhitelistEnterSubGateFactory internal factory;
    address internal caller = makeAddr("caller");
    address internal creditRoleSetter = makeAddr("creditRoleSetter");
    address internal debtRoleSetter = makeAddr("debtRoleSetter");

    function setUp() public {
        factory = new WhitelistEnterSubGateFactory();
    }

    function _expectedGate(
        address _creditRoleSetter,
        address _debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt,
        address _caller
    ) internal view returns (address) {
        // forge-lint: disable-next-item(encode-packed-collision)
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(WhitelistEnterSubGate).creationCode,
                abi.encode(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen)
            )
        );
        return vm.computeCreate2Address(keccak256(abi.encode(preSalt, _caller)), initCodeHash, address(factory));
    }

    function testCreateWhitelistEnterSubGate(
        address _creditRoleSetter,
        address _debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) public {
        address expected = _expectedGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, preSalt, caller);
        bytes32 salt = keccak256(abi.encode(preSalt, caller));
        assertEq(
            factory.whitelistEnterSubGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, salt), address(0)
        );

        vm.expectEmit();
        emit IWhitelistEnterSubGateFactory.CreateWhitelistEnterSubGate(
            caller, expected, _creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, preSalt
        );
        vm.prank(caller);
        address gateAddress =
            factory.createWhitelistEnterSubGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, preSalt);

        assertEq(gateAddress, expected);
        assertTrue(factory.isCreated(gateAddress));
        assertEq(
            factory.whitelistEnterSubGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, salt), gateAddress
        );
        WhitelistEnterSubGate gate = WhitelistEnterSubGate(gateAddress);
        assertEq(gate.roleSetter(true), _creditRoleSetter);
        assertEq(gate.roleSetter(false), _debtRoleSetter);
        assertEq(gate.CREDIT_OPEN(), creditOpen);
        assertEq(gate.DEBT_OPEN(), debtOpen);
    }

    function testCreateWhitelistEnterSubGateSamePreSaltReverts(bytes32 preSalt) public {
        factory.createWhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);

        vm.expectRevert();
        factory.createWhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);
    }

    function testCreateWhitelistEnterSubGateDifferentCallers(bytes32 preSalt, address caller1, address caller2) public {
        vm.assume(caller1 != caller2);

        vm.prank(caller1);
        address gate1 = factory.createWhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);
        vm.prank(caller2);
        address gate2 = factory.createWhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);

        assertEq(gate1, _expectedGate(creditRoleSetter, debtRoleSetter, false, false, preSalt, caller1));
        assertEq(gate2, _expectedGate(creditRoleSetter, debtRoleSetter, false, false, preSalt, caller2));
        assertTrue(gate1 != gate2);
        assertTrue(factory.isCreated(gate1));
        assertTrue(factory.isCreated(gate2));
        assertEq(
            factory.whitelistEnterSubGate(
                creditRoleSetter, debtRoleSetter, false, false, keccak256(abi.encode(preSalt, caller1))
            ),
            gate1
        );
        assertEq(
            factory.whitelistEnterSubGate(
                creditRoleSetter, debtRoleSetter, false, false, keccak256(abi.encode(preSalt, caller2))
            ),
            gate2
        );
    }

    function testCreateWhitelistEnterSubGateDifferentPreSalts(bytes32 preSalt1, bytes32 preSalt2) public {
        vm.assume(preSalt1 != preSalt2);

        address gate1 = factory.createWhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, false, preSalt1);
        address gate2 = factory.createWhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, false, preSalt2);

        assertTrue(gate1 != gate2);
        assertTrue(factory.isCreated(gate1));
        assertTrue(factory.isCreated(gate2));
        assertEq(
            factory.whitelistEnterSubGate(
                creditRoleSetter, debtRoleSetter, false, false, keccak256(abi.encode(preSalt1, address(this)))
            ),
            gate1
        );
        assertEq(
            factory.whitelistEnterSubGate(
                creditRoleSetter, debtRoleSetter, false, false, keccak256(abi.encode(preSalt2, address(this)))
            ),
            gate2
        );
    }

    function testCreateWhitelistEnterSubGateDifferentArgs(bytes32 preSalt) public {
        bytes32 salt = keccak256(abi.encode(preSalt, address(this)));
        address otherCreditRoleSetter = makeAddr("otherCreditRoleSetter");
        address otherDebtRoleSetter = makeAddr("otherDebtRoleSetter");
        address gate1 = factory.createWhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);
        address gate2 = factory.createWhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, true, false, preSalt);
        address gate3 = factory.createWhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, true, preSalt);
        address gate4 =
            factory.createWhitelistEnterSubGate(otherCreditRoleSetter, debtRoleSetter, false, false, preSalt);
        address gate5 =
            factory.createWhitelistEnterSubGate(creditRoleSetter, otherDebtRoleSetter, false, false, preSalt);

        assertTrue(gate1 != gate2);
        assertTrue(factory.isCreated(gate1));
        assertTrue(factory.isCreated(gate2));
        assertTrue(factory.isCreated(gate3));
        assertTrue(factory.isCreated(gate4));
        assertTrue(factory.isCreated(gate5));
        assertEq(factory.whitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, false, salt), gate1);
        assertEq(factory.whitelistEnterSubGate(creditRoleSetter, debtRoleSetter, true, false, salt), gate2);
        assertEq(factory.whitelistEnterSubGate(creditRoleSetter, debtRoleSetter, false, true, salt), gate3);
        assertEq(factory.whitelistEnterSubGate(otherCreditRoleSetter, debtRoleSetter, false, false, salt), gate4);
        assertEq(factory.whitelistEnterSubGate(creditRoleSetter, otherDebtRoleSetter, false, false, salt), gate5);
    }

    function testIsCreatedFalseForUnknownAddress(address account) public view {
        assertFalse(factory.isCreated(account));
    }
}
