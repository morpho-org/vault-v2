// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEnterGate} from "../../lib/midnight/src/interfaces/IGate.sol";
import {WrapperEnterGate} from "../../src/periphery/gates/WrapperEnterGate.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {EnterGateMock} from "../mocks/EnterGateMock.sol";

contract WrapperEnterGateTest is Test {
    ERC20Mock internal vault;
    EnterGateMock internal gate;
    WrapperEnterGate internal wrapper;
    address internal adapter = makeAddr("adapter");
    address internal depositor = makeAddr("depositor");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        vault = new ERC20Mock(18);
        gate = new EnterGateMock();
        wrapper = new WrapperEnterGate(adapter, address(vault), address(gate));
    }

    function testConstructor() public view {
        assertEq(wrapper.adapter(), adapter);
        assertEq(wrapper.vault(), address(vault));
        assertEq(wrapper.gate(), address(gate));
    }

    function testAdapterCreditBypassesBalanceAndGate() public {
        vm.mockCallRevert(address(vault), abi.encodeCall(vault.balanceOf, (adapter)), "balance reverted");
        vm.mockCallRevert(address(gate), abi.encodeCall(IEnterGate.canIncreaseCredit, (adapter)), "gate reverted");

        assertTrue(wrapper.canIncreaseCredit(adapter));
    }

    function testDepositorCreditBypassesGate(uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);
        deal(address(vault), depositor, shares);
        vm.mockCallRevert(address(gate), abi.encodeCall(IEnterGate.canIncreaseCredit, (depositor)), "gate reverted");

        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditForwarded(address account, bool allowed) public {
        vm.assume(account != adapter);
        gate.setCanIncreaseCredit(account, allowed);
        gate.setCanIncreaseDebt(account, !allowed);

        vm.expectCall(address(gate), abi.encodeCall(IEnterGate.canIncreaseCredit, (account)));
        assertEq(wrapper.canIncreaseCredit(account), allowed);
    }

    function testCreditUsesAccountNotCaller() public {
        deal(address(vault), depositor, 1);

        vm.prank(depositor);
        assertFalse(wrapper.canIncreaseCredit(recipient));
        vm.prank(recipient);
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditTracksShareTransfers(uint256 shares) public {
        shares = bound(shares, 2, type(uint128).max);
        deal(address(vault), depositor, shares);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.canIncreaseCredit(recipient));

        vm.prank(depositor);
        vault.transfer(recipient, shares - 1);
        assertTrue(wrapper.canIncreaseCredit(depositor), "one share is enough");
        assertTrue(wrapper.canIncreaseCredit(recipient));

        vm.prank(depositor);
        vault.transfer(recipient, 1);
        assertFalse(wrapper.canIncreaseCredit(depositor), "no authorization retained in the same transaction");
        assertTrue(wrapper.canIncreaseCredit(recipient));
    }

    function testCreditFallsBackToGateAfterSharesRemoved(bool allowed) public {
        deal(address(vault), depositor, 1);
        gate.setCanIncreaseCredit(depositor, allowed);
        assertTrue(wrapper.canIncreaseCredit(depositor));

        vm.prank(depositor);
        vault.transfer(recipient, 1);

        vm.expectCall(address(gate), abi.encodeCall(IEnterGate.canIncreaseCredit, (depositor)));
        assertEq(wrapper.canIncreaseCredit(depositor), allowed);
    }

    function testCreditDoesNotAcceptSharesOfAnotherVault(uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);
        ERC20Mock otherVault = new ERC20Mock(18);
        deal(address(otherVault), depositor, shares);

        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditBubblesGateRevert() public {
        vm.mockCallRevert(address(gate), abi.encodeCall(IEnterGate.canIncreaseCredit, (depositor)), "gate reverted");

        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseCredit(depositor);
    }

    function testDebtForwarded(address account, uint256 shares, bool allowed) public {
        shares = bound(shares, 0, type(uint128).max);
        deal(address(vault), account, shares);
        gate.setCanIncreaseDebt(account, allowed);
        gate.setCanIncreaseCredit(account, !allowed);

        vm.expectCall(address(gate), abi.encodeCall(IEnterGate.canIncreaseDebt, (account)));
        assertEq(wrapper.canIncreaseDebt(account), allowed);
    }

    function testAdapterDebtForwarded(bool allowed) public {
        gate.setCanIncreaseDebt(adapter, allowed);

        vm.expectCall(address(gate), abi.encodeCall(IEnterGate.canIncreaseDebt, (adapter)));
        assertEq(wrapper.canIncreaseDebt(adapter), allowed);
    }

    function testDebtBubblesGateRevertForDepositorAndAdapter(bool isAdapter) public {
        address account = isAdapter ? adapter : depositor;
        deal(address(vault), account, 1);
        vm.mockCallRevert(address(gate), abi.encodeCall(IEnterGate.canIncreaseDebt, (account)), "gate reverted");

        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseDebt(account);
    }
}
