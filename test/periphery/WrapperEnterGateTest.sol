// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEnterGate} from "../../lib/midnight/src/interfaces/IGate.sol";
import {IMidnight, Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../../lib/midnight/src/libraries/IdLib.sol";
import {IMidnightAdapterBase} from "../../src/adapters/interfaces/IMidnightAdapter.sol";
import {WrapperEnterGate} from "../../src/periphery/gates/WrapperEnterGate.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {EnterGateMock} from "../mocks/EnterGateMock.sol";
import {MidnightAdapterFactoryMock} from "../mocks/MidnightAdapterFactoryMock.sol";

/// forge-config: default.isolate = false
contract WrapperEnterGateTest is Test {
    ERC20Mock internal vault;
    EnterGateMock internal gate;
    MidnightAdapterFactoryMock internal adapterFactory;
    WrapperEnterGate internal wrapper;
    address internal midnight = makeAddr("midnight");
    Market internal market;
    address internal adapter = makeAddr("adapter");
    address internal depositor = makeAddr("depositor");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        vault = new ERC20Mock(18);
        gate = new EnterGateMock();
        market.midnight = midnight;
        vm.mockCall(adapter, abi.encodeCall(IMidnightAdapterBase.parentVault, ()), abi.encode(address(vault)));
        adapterFactory = new MidnightAdapterFactoryMock();
        adapterFactory.setIsMidnightAdapter(adapter, true);
        wrapper = new WrapperEnterGate(address(gate), address(adapterFactory), market);
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (wrapper.marketId(), adapter)), abi.encode(uint128(1)));
    }

    function testConstructor() public view {
        assertEq(wrapper.midnight(), midnight);
        Market memory expectedMarket = market;
        expectedMarket.enterGate = address(wrapper);
        assertEq(wrapper.marketId(), IdLib.toId(expectedMarket));
        assertEq(wrapper.gate(), address(gate));
        assertEq(wrapper.adapterFactory(), address(adapterFactory));
    }

    function testAdapterCreditForwarded(bool allowed) public {
        gate.setCanIncreaseCredit(adapter, allowed);
        assertEq(wrapper.canIncreaseCredit(adapter), allowed);
    }

    function testTransientAllowIncreaseCredit(address caller, uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);
        deal(address(vault), depositor, shares);
        assertFalse(wrapper.canIncreaseCredit(depositor));
        vm.prank(caller);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.isTransientlyAllowed(depositor));
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.isTransientlyAllowed(recipient));
    }

    /// forge-config: default.isolate = true
    function testAuthorizationClearedAfterTransaction() public {
        deal(address(vault), depositor, 1);
        this.allowAndCheckUser();
        assertFalse(wrapper.isTransientlyAllowed(depositor));
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function allowAndCheckUser() external {
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.isTransientlyAllowed(depositor));
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testTransientAllowIncreaseCreditRequiresShares() public {
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.isTransientlyAllowed(depositor));
    }

    function testTransientAllowIncreaseCreditUsesParentVault() public {
        ERC20Mock otherVault = new ERC20Mock(18);
        deal(address(otherVault), depositor, 1);
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.isTransientlyAllowed(depositor));

        vm.mockCall(adapter, abi.encodeCall(IMidnightAdapterBase.parentVault, ()), abi.encode(address(otherVault)));
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.isTransientlyAllowed(depositor));
    }

    function testAuthorizationRevertsWithCaller() public {
        deal(address(vault), depositor, 1);
        vm.expectRevert(bytes("reverted"));
        this.allowAndRevert();
        assertFalse(wrapper.isTransientlyAllowed(depositor));
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function allowAndRevert() external {
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        revert("reverted");
    }

    function testCreditRequiresMarketPosition(bool allowed) public {
        deal(address(vault), depositor, 1);
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (wrapper.marketId(), adapter)), abi.encode(uint128(0)));
        gate.setCanIncreaseCredit(depositor, allowed);
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.isTransientlyAllowed(depositor));
        assertEq(wrapper.canIncreaseCredit(depositor), allowed);
    }

    function testCreditDoesNotAcceptPositionInAnotherMarket(bytes32 otherMarketId) public {
        vm.assume(otherMarketId != wrapper.marketId());
        deal(address(vault), depositor, 1);
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (wrapper.marketId(), adapter)), abi.encode(uint128(0)));
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (otherMarketId, adapter)), abi.encode(uint128(1)));
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testMultipleVaults() public {
        ERC20Mock otherVault = new ERC20Mock(18);
        address otherAdapter = makeAddr("otherAdapter");
        vm.mockCall(otherAdapter, abi.encodeCall(IMidnightAdapterBase.parentVault, ()), abi.encode(address(otherVault)));
        adapterFactory.setIsMidnightAdapter(otherAdapter, true);
        vm.mockCall(
            midnight, abi.encodeCall(IMidnight.credit, (wrapper.marketId(), otherAdapter)), abi.encode(uint128(1))
        );
        deal(address(vault), depositor, 1);
        deal(address(otherVault), recipient, 1);

        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        wrapper.transientAllowIncreaseCredit(recipient, otherAdapter);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertTrue(wrapper.canIncreaseCredit(recipient));
    }

    function testOnlyAdaptersCanAllow() public {
        address creditor = makeAddr("creditor");
        vm.mockCall(creditor, abi.encodeCall(IMidnightAdapterBase.parentVault, ()), abi.encode(address(vault)));
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (wrapper.marketId(), creditor)), abi.encode(uint128(1)));
        deal(address(vault), depositor, 1);
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, creditor);
        assertFalse(wrapper.canIncreaseCredit(depositor));

        adapterFactory.setIsMidnightAdapter(creditor, true);
        wrapper.transientAllowIncreaseCredit(depositor, creditor);
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testAdaptersCannotBeAllowed() public {
        address otherAdapter = makeAddr("otherAdapter");
        adapterFactory.setIsMidnightAdapter(otherAdapter, true);
        deal(address(vault), otherAdapter, 1);
        deal(address(vault), adapter, 1);
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(otherAdapter, adapter);
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(adapter, adapter);
        assertFalse(wrapper.canIncreaseCredit(otherAdapter));
        assertFalse(wrapper.canIncreaseCredit(adapter));

        adapterFactory.setIsMidnightAdapter(otherAdapter, false);
        wrapper.transientAllowIncreaseCredit(otherAdapter, adapter);
        assertTrue(wrapper.canIncreaseCredit(otherAdapter));
    }

    function testDepositorCreditBypassesGate(uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);
        deal(address(vault), depositor, shares);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
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
        vm.prank(recipient);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);

        vm.prank(depositor);
        assertFalse(wrapper.canIncreaseCredit(recipient));
        vm.prank(recipient);
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testAuthorizationSurvivesShareTransfersWithinTransaction(uint256 shares) public {
        shares = bound(shares, 2, type(uint128).max);
        deal(address(vault), depositor, shares);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.canIncreaseCredit(recipient));

        vm.prank(depositor);
        vault.transfer(recipient, shares - 1);
        assertTrue(wrapper.canIncreaseCredit(depositor), "one share is enough");
        assertFalse(wrapper.canIncreaseCredit(recipient));
        wrapper.transientAllowIncreaseCredit(recipient, adapter);

        vm.prank(depositor);
        vault.transfer(recipient, 1);
        assertTrue(wrapper.canIncreaseCredit(depositor), "authorization retained until the end of the transaction");
        assertTrue(wrapper.canIncreaseCredit(recipient));
    }

    function testAuthorizationSurvivesCreditRemovalWithinTransaction() public {
        deal(address(vault), depositor, 1);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.canIncreaseCredit(depositor));

        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (wrapper.marketId(), adapter)), abi.encode(uint128(0)));
        assertTrue(wrapper.canIncreaseCredit(depositor));

        deal(address(vault), recipient, 1);
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(recipient, adapter);
        assertFalse(wrapper.canIncreaseCredit(recipient));
    }

    function testCreditDoesNotAcceptSharesOfAnotherVault(uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);
        ERC20Mock otherVault = new ERC20Mock(18);
        deal(address(otherVault), depositor, shares);

        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditBubblesGateRevert() public {
        vm.mockCallRevert(address(gate), abi.encodeCall(IEnterGate.canIncreaseCredit, (depositor)), "gate reverted");

        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseCredit(depositor);
    }

    function testDebtForwarded(address account, uint256 shares, bool allowed) public {
        vm.assume(account != adapter);
        shares = bound(shares, 0, type(uint128).max);
        deal(address(vault), account, shares);
        if (shares > 0) wrapper.transientAllowIncreaseCredit(account, adapter);
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
        deal(address(vault), depositor, 1);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        vm.mockCallRevert(address(gate), abi.encodeCall(IEnterGate.canIncreaseDebt, (account)), "gate reverted");

        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseDebt(account);
    }
}
