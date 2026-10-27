// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

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
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        vm.setEvmVersion("osaka");
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
        wrapper = new VaultV2CompatibleEnterGate(address(subGate));
        vm.prank(creditRoleSetter);
        wrapper.addAdmitterFactory(address(adapterFactory));
    }

    function testConstructor() public view {
        assertEq(wrapper.subGate(), address(subGate));
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
        assertFalse(wrapper.canIncreaseCredit(depositor));
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.canIncreaseCredit(recipient));
    }

    function testAdmitEmitsEvent() public {
        vm.expectEmit();
        emit IVaultV2CompatibleEnterGate.Admit(adapter, depositor, address(adapterFactory));
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
    }

    function testEmptyAdmissionDoesNotAdmitZeroAddress() public {
        assertFalse(wrapper.canIncreaseCredit(address(0)));
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        assertFalse(wrapper.canIncreaseCredit(address(0)));
        wrapper.unadmit();
        assertFalse(wrapper.canIncreaseCredit(address(0)));
    }

    function testAdmitRequiresAllowedFactory() public {
        MidnightAdapterFactoryMock otherFactory = new MidnightAdapterFactoryMock();
        otherFactory.setIsCreated(adapter, true);
        vm.expectRevert(IVaultV2CompatibleEnterGate.Unauthorized.selector);
        vm.prank(adapter);
        wrapper.admit(depositor, address(otherFactory));
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testAdmitRequiresFactoryMembership(address caller) public {
        vm.assume(caller != adapter);
        vm.expectRevert(IVaultV2CompatibleEnterGate.Unauthorized.selector);
        vm.prank(caller);
        wrapper.admit(depositor, address(adapterFactory));
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testAdmissionReplacesPreviousBuyer() public {
        vm.startPrank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        wrapper.admit(recipient, address(adapterFactory));
        vm.stopPrank();
        assertFalse(wrapper.canIncreaseCredit(depositor));
        assertTrue(wrapper.canIncreaseCredit(recipient));
    }

    function testUnadmit(address caller) public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        vm.prank(caller);
        wrapper.unadmit();
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    /// forge-config: default.isolate = true
    function testAuthorizationClearedAfterTransaction() public {
        this.admitAndCheckUser();
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function admitAndCheckUser() external {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testAuthorizationRevertsWithCaller() public {
        vm.expectRevert(bytes("reverted"));
        this.admitAndRevert();
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function admitAndRevert() external {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        revert("reverted");
    }

    function testAdmittedCreditBypassesSubGate() public {
        vm.mockCallRevert(
            address(subGate), abi.encodeCall(IEnterSubGate.creditIncreaseAllowed, (depositor)), "gate reverted"
        );
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditForwarded(address account, bool allowed) public {
        vm.assume(account != address(0));
        subGate.setIsWhitelisted(true, account, allowed);
        subGate.setIsWhitelisted(false, account, !allowed);
        vm.expectCall(address(subGate), abi.encodeCall(IEnterSubGate.creditIncreaseAllowed, (account)));
        assertEq(wrapper.canIncreaseCredit(account), allowed);
    }

    function testCreditUsesAccountNotCaller() public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        vm.prank(depositor);
        assertFalse(wrapper.canIncreaseCredit(recipient));
        vm.prank(recipient);
        assertTrue(wrapper.canIncreaseCredit(depositor));
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
        wrapper.admit(account, address(adapterFactory));
        subGate.setIsWhitelisted(false, account, allowed);
        subGate.setIsWhitelisted(true, account, !allowed);
        vm.expectCall(address(subGate), abi.encodeCall(IEnterSubGate.debtIncreaseAllowed, (account)));
        assertEq(wrapper.canIncreaseDebt(account), allowed);
    }

    function testDebtBubblesSubGateRevert() public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        vm.mockCallRevert(
            address(subGate), abi.encodeCall(IEnterSubGate.debtIncreaseAllowed, (depositor)), "gate reverted"
        );
        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseDebt(depositor);
    }

    function testSharedSubGateSharesWhitelist() public {
        VaultV2CompatibleEnterGate otherWrapper = new VaultV2CompatibleEnterGate(address(subGate));
        subGate.setIsWhitelisted(true, depositor, true);
        subGate.setIsWhitelisted(false, recipient, true);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertTrue(otherWrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.canIncreaseDebt(depositor));
        assertFalse(otherWrapper.canIncreaseDebt(depositor));
        assertTrue(wrapper.canIncreaseDebt(recipient));
        assertTrue(otherWrapper.canIncreaseDebt(recipient));
    }

    function testSharedSubGateKeepsAdmissionsAndFactoriesSeparate() public {
        VaultV2CompatibleEnterGate otherWrapper = new VaultV2CompatibleEnterGate(address(subGate));
        assertFalse(otherWrapper.canAdmit(address(adapterFactory)));
        vm.expectRevert(IVaultV2CompatibleEnterGate.Unauthorized.selector);
        vm.prank(adapter);
        otherWrapper.admit(depositor, address(adapterFactory));

        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertFalse(otherWrapper.canIncreaseCredit(depositor));

        vm.prank(creditRoleSetter);
        otherWrapper.addAdmitterFactory(address(adapterFactory));
        vm.prank(adapter);
        otherWrapper.admit(recipient, address(adapterFactory));
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.canIncreaseCredit(recipient));
        assertFalse(otherWrapper.canIncreaseCredit(depositor));
        assertTrue(otherWrapper.canIncreaseCredit(recipient));

        wrapper.unadmit();
        assertFalse(wrapper.canIncreaseCredit(depositor));
        assertTrue(otherWrapper.canIncreaseCredit(recipient));
    }

    function testSharedSubGateRoleSetterChangesForBothWrappers() public {
        VaultV2CompatibleEnterGate otherWrapper = new VaultV2CompatibleEnterGate(address(subGate));
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
        VaultV2CompatibleEnterGate first = new VaultV2CompatibleEnterGate(openSubGate);
        VaultV2CompatibleEnterGate second = new VaultV2CompatibleEnterGate(openSubGate);
        assertEq(first.canIncreaseCredit(depositor), creditOpen);
        assertEq(second.canIncreaseCredit(depositor), creditOpen);
        assertEq(first.canIncreaseDebt(depositor), debtOpen);
        assertEq(second.canIncreaseDebt(depositor), debtOpen);
    }
}
