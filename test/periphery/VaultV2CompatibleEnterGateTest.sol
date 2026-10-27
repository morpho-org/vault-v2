// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {Test} from "forge-std/Test.sol";
import {IEnterSubGate} from "../../src/periphery/gates/interfaces/IEnterSubGate.sol";
import {IWhitelistEnterSubGate} from "../../src/periphery/gates/interfaces/IWhitelistEnterSubGate.sol";
import {VaultV2CompatibleEnterGate} from "../../src/periphery/gates/VaultV2CompatibleEnterGate.sol";
import {IVaultV2CompatibleEnterGate} from "../../src/periphery/gates/interfaces/IVaultV2CompatibleEnterGate.sol";
import {MidnightAdapterFactoryMock} from "../mocks/MidnightAdapterFactoryMock.sol";

/// forge-config: default.isolate = false
contract VaultV2CompatibleEnterGateTest is Test {
    IWhitelistEnterSubGate internal subGate;
    MidnightAdapterFactoryMock internal adapterFactory;
    VaultV2CompatibleEnterGate internal wrapper;
    address internal creditRoleSetter = makeAddr("creditRoleSetter");
    address internal debtRoleSetter = makeAddr("debtRoleSetter");
    address internal adapter = makeAddr("adapter");
    address internal depositor = makeAddr("depositor");
    address internal midnight = makeAddr("midnight");
    bytes32 internal marketId = bytes32("market");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        vm.setEvmVersion("osaka");
        vm.mockCall(midnight, abi.encodeCall(IMidnight.liquidationLocked, (marketId, adapter)), abi.encode(false));
        subGate = IWhitelistEnterSubGate(
            deployCode(
                "WhitelistEnterSubGate.sol:WhitelistEnterSubGate:default",
                abi.encode(creditRoleSetter, debtRoleSetter, false, false)
            )
        );
        vm.prank(creditRoleSetter);
        subGate.setIsWhitelister(true, address(this), true);
        vm.prank(debtRoleSetter);
        subGate.setIsWhitelister(false, address(this), true);
        adapterFactory = new MidnightAdapterFactoryMock();
        adapterFactory.setIsCreated(adapter, true);
        wrapper = new VaultV2CompatibleEnterGate(address(subGate), address(midnight));
        vm.prank(creditRoleSetter);
        wrapper.addAdmitterFactory(address(adapterFactory));
    }

    function testConstructor() public view {
        assertEq(wrapper.subGate(), address(subGate));
        assertEq(wrapper.midnight(), midnight);
        assertEq(wrapper.roleSetter(), creditRoleSetter);
        assertTrue(wrapper.canAdmit(address(adapterFactory)));
    }

    function testAddAdmitterFactory(address factory) public {
        vm.expectEmit();
        emit IVaultV2CompatibleEnterGate.AddAdmitterFactory(factory);
        vm.prank(creditRoleSetter);
        wrapper.addAdmitterFactory(factory);
        assertTrue(wrapper.canAdmit(factory));
        assertTrue(wrapper.canAdmit(address(adapterFactory)));
    }

    function testAddAdmitterFactoryRequiresCreditRoleSetter(address caller) public {
        vm.assume(caller != creditRoleSetter);
        vm.expectRevert(IVaultV2CompatibleEnterGate.Unauthorized.selector);
        vm.prank(caller);
        wrapper.addAdmitterFactory(makeAddr("otherFactory"));
    }

    function testAdmit() public {
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(depositor));
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.prank(midnight);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(recipient));
    }

    function testAdmissionBlockedDuringSale(bool ordinaryApproval) public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.mockCall(midnight, abi.encodeCall(IMidnight.liquidationLocked, (marketId, adapter)), abi.encode(true));
        subGate.setIsWhitelisted(true, depositor, ordinaryApproval);
        vm.prank(midnight);
        assertEq(wrapper.canIncreaseCredit(depositor), ordinaryApproval);
    }

    function testAdmissionBubblesLockCheckRevert() public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.mockCallRevert(midnight, abi.encodeCall(IMidnight.liquidationLocked, (marketId, adapter)), "lock reverted");
        vm.expectRevert(bytes("lock reverted"));
        vm.prank(midnight);
        wrapper.canIncreaseCredit(depositor);
    }

    function testAdmitEmitsEvent() public {
        vm.expectEmit();
        emit IVaultV2CompatibleEnterGate.Admit(adapter, depositor, address(adapterFactory));
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
    }

    function testEmptyAdmissionDoesNotAdmitZeroAddress() public {
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(address(0)));
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(address(0)));
        wrapper.unadmit();
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(address(0)));
    }

    function testAdmitRequiresAllowedFactory() public {
        MidnightAdapterFactoryMock otherFactory = new MidnightAdapterFactoryMock();
        otherFactory.setIsCreated(adapter, true);
        vm.expectRevert(IVaultV2CompatibleEnterGate.Unauthorized.selector);
        vm.prank(adapter);
        wrapper.admit(depositor, address(otherFactory), marketId);
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testAdmitRequiresFactoryMembership(address caller) public {
        vm.assume(caller != adapter);
        vm.expectRevert(IVaultV2CompatibleEnterGate.Unauthorized.selector);
        vm.prank(caller);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testAdmissionReplacesPreviousBuyer() public {
        vm.startPrank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        wrapper.admit(recipient, address(adapterFactory), marketId);
        vm.stopPrank();
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(depositor));
        vm.prank(midnight);
        assertTrue(wrapper.canIncreaseCredit(recipient));
    }

    function testUnadmit(address caller) public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.prank(caller);
        wrapper.unadmit();
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    /// forge-config: default.isolate = true
    function testAuthorizationClearedAfterTransaction() public {
        this.admitAndCheckUser();
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function admitAndCheckUser() external {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.prank(midnight);
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testAuthorizationRevertsWithCaller() public {
        vm.expectRevert(bytes("reverted"));
        this.admitAndRevert();
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function admitAndRevert() external {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        revert("reverted");
    }

    function testAdmittedCreditBypassesSubGate() public {
        vm.mockCallRevert(
            address(subGate), abi.encodeCall(IEnterSubGate.creditIncreaseAllowed, (depositor)), "gate reverted"
        );
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.prank(midnight);
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditForwarded(address account, bool allowed) public {
        vm.assume(account != address(0));
        subGate.setIsWhitelisted(true, account, allowed);
        subGate.setIsWhitelisted(false, account, !allowed);
        vm.expectCall(address(subGate), abi.encodeCall(IEnterSubGate.creditIncreaseAllowed, (account)));
        vm.prank(midnight);
        assertEq(wrapper.canIncreaseCredit(account), allowed);
    }

    function testCreditAdmissionRequiresMidnight() public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.prank(depositor);
        assertFalse(wrapper.canIncreaseCredit(recipient));
        vm.prank(recipient);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditBubblesSubGateRevert() public {
        vm.mockCallRevert(
            address(subGate), abi.encodeCall(IEnterSubGate.creditIncreaseAllowed, (depositor)), "gate reverted"
        );
        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseCredit(depositor);
    }

    function testDebtForwarded(address account, bool allowed) public {
        vm.prank(adapter);
        wrapper.admit(account, address(adapterFactory), marketId);
        subGate.setIsWhitelisted(false, account, allowed);
        subGate.setIsWhitelisted(true, account, !allowed);
        vm.expectCall(address(subGate), abi.encodeCall(IEnterSubGate.debtIncreaseAllowed, (account)));
        assertEq(wrapper.canIncreaseDebt(account), allowed);
    }

    function testDebtBubblesSubGateRevert() public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.mockCallRevert(
            address(subGate), abi.encodeCall(IEnterSubGate.debtIncreaseAllowed, (depositor)), "gate reverted"
        );
        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseDebt(depositor);
    }

    function testSharedSubGateSharesWhitelist() public {
        VaultV2CompatibleEnterGate otherWrapper = new VaultV2CompatibleEnterGate(address(subGate), address(midnight));
        subGate.setIsWhitelisted(true, depositor, true);
        subGate.setIsWhitelisted(false, recipient, true);
        vm.prank(midnight);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        vm.prank(midnight);
        assertTrue(otherWrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.canIncreaseDebt(depositor));
        assertFalse(otherWrapper.canIncreaseDebt(depositor));
        assertTrue(wrapper.canIncreaseDebt(recipient));
        assertTrue(otherWrapper.canIncreaseDebt(recipient));
    }

    function testSharedSubGateKeepsAdmissionsAndFactoriesSeparate() public {
        VaultV2CompatibleEnterGate otherWrapper = new VaultV2CompatibleEnterGate(address(subGate), address(midnight));
        assertFalse(otherWrapper.canAdmit(address(adapterFactory)));
        vm.expectRevert(IVaultV2CompatibleEnterGate.Unauthorized.selector);
        vm.prank(adapter);
        otherWrapper.admit(depositor, address(adapterFactory), marketId);

        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory), marketId);
        vm.prank(midnight);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        vm.prank(midnight);
        assertFalse(otherWrapper.canIncreaseCredit(depositor));

        vm.prank(creditRoleSetter);
        otherWrapper.addAdmitterFactory(address(adapterFactory));
        vm.prank(adapter);
        otherWrapper.admit(recipient, address(adapterFactory), marketId);
        vm.prank(midnight);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(recipient));
        vm.prank(midnight);
        assertFalse(otherWrapper.canIncreaseCredit(depositor));
        vm.prank(midnight);
        assertTrue(otherWrapper.canIncreaseCredit(recipient));

        wrapper.unadmit();
        vm.prank(midnight);
        assertFalse(wrapper.canIncreaseCredit(depositor));
        vm.prank(midnight);
        assertTrue(otherWrapper.canIncreaseCredit(recipient));
    }

    function testSharedSubGateRoleSetterChangesForBothWrappers() public {
        VaultV2CompatibleEnterGate otherWrapper = new VaultV2CompatibleEnterGate(address(subGate), address(midnight));
        address newRoleSetter = makeAddr("newRoleSetter");
        vm.prank(creditRoleSetter);
        subGate.setRoleSetter(true, newRoleSetter);
        assertEq(wrapper.roleSetter(), newRoleSetter);
        assertEq(otherWrapper.roleSetter(), newRoleSetter);

        vm.expectRevert(IVaultV2CompatibleEnterGate.Unauthorized.selector);
        vm.prank(creditRoleSetter);
        otherWrapper.addAdmitterFactory(address(adapterFactory));
        vm.prank(newRoleSetter);
        otherWrapper.addAdmitterFactory(address(adapterFactory));
        assertTrue(wrapper.canAdmit(address(adapterFactory)), "existing registration remains");
        assertTrue(otherWrapper.canAdmit(address(adapterFactory)));
    }

    function testSharedSubGateOpenSides(bool creditOpen, bool debtOpen) public {
        address openSubGate = deployCode(
            "WhitelistEnterSubGate.sol:WhitelistEnterSubGate:default",
            abi.encode(creditRoleSetter, debtRoleSetter, creditOpen, debtOpen)
        );
        VaultV2CompatibleEnterGate first = new VaultV2CompatibleEnterGate(openSubGate, address(midnight));
        VaultV2CompatibleEnterGate second = new VaultV2CompatibleEnterGate(openSubGate, address(midnight));
        vm.prank(midnight);
        assertEq(first.canIncreaseCredit(depositor), creditOpen);
        vm.prank(midnight);
        assertEq(second.canIncreaseCredit(depositor), creditOpen);
        assertEq(first.canIncreaseDebt(depositor), debtOpen);
        assertEq(second.canIncreaseDebt(depositor), debtOpen);
    }
}
