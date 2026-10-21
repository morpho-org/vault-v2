// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEnterSubGate} from "../../src/periphery/gates/interfaces/IEnterSubGate.sol";
import {IMidnight, Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../../lib/midnight/src/libraries/IdLib.sol";
import {IWhitelistEnterSubGate} from "../../src/periphery/gates/interfaces/IWhitelistEnterSubGate.sol";
import {VaultV2CompatibleEnterGate} from "../../src/periphery/gates/VaultV2CompatibleEnterGate.sol";
import {IVaultV2CompatibleEnterGate} from "../../src/periphery/gates/interfaces/IVaultV2CompatibleEnterGate.sol";
import {MidnightAdapterFactoryMock} from "../mocks/MidnightAdapterFactoryMock.sol";

/// forge-config: default.isolate = false
contract VaultV2CompatibleEnterGateTest is Test {
    IWhitelistEnterSubGate internal subGate;
    MidnightAdapterFactoryMock internal adapterFactory;
    VaultV2CompatibleEnterGate internal wrapper;
    address internal midnight = makeAddr("midnight");
    Market internal market;
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
        market.midnight = midnight;
        adapterFactory = new MidnightAdapterFactoryMock();
        adapterFactory.setIsCreated(adapter, true);
        wrapper = new VaultV2CompatibleEnterGate(address(subGate), market);
        vm.prank(creditRoleSetter);
        wrapper.addAdmitterFactory(address(adapterFactory));
        vm.mockCall(
            midnight, abi.encodeCall(IMidnight.liquidationLocked, (wrapper.marketId(), adapter)), abi.encode(false)
        );
    }

    function testConstructor() public view {
        assertEq(wrapper.midnight(), midnight);
        Market memory expectedMarket = market;
        expectedMarket.enterGate = address(wrapper);
        assertEq(wrapper.marketId(), IdLib.toId(expectedMarket));
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

    function testAdmissionDisabledDuringAdmitterLiquidationLock() public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        assertTrue(wrapper.canIncreaseCredit(depositor));
        vm.mockCall(
            midnight, abi.encodeCall(IMidnight.liquidationLocked, (wrapper.marketId(), adapter)), abi.encode(true)
        );
        assertFalse(wrapper.canIncreaseCredit(depositor));
        subGate.setIsWhitelisted(wrapper.marketId(), true, depositor, true);
        assertTrue(wrapper.canIncreaseCredit(depositor), "ordinary approval still applies");
    }

    function testAdmissionIgnoresOtherMarketLock(bytes32 otherMarketId) public {
        vm.assume(otherMarketId != wrapper.marketId());
        vm.mockCall(midnight, abi.encodeCall(IMidnight.liquidationLocked, (otherMarketId, adapter)), abi.encode(true));
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        assertTrue(wrapper.canIncreaseCredit(depositor));
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
            address(subGate),
            abi.encodeCall(IEnterSubGate.canIncreaseCredit, (wrapper.marketId(), depositor)),
            "gate reverted"
        );
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditForwarded(address account, bool allowed) public {
        vm.assume(account != address(0));
        subGate.setIsWhitelisted(wrapper.marketId(), true, account, allowed);
        subGate.setIsWhitelisted(wrapper.marketId(), false, account, !allowed);
        vm.expectCall(address(subGate), abi.encodeCall(IEnterSubGate.canIncreaseCredit, (wrapper.marketId(), account)));
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
            address(subGate),
            abi.encodeCall(IEnterSubGate.canIncreaseCredit, (wrapper.marketId(), depositor)),
            "gate reverted"
        );
        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseCredit(depositor);
    }

    function testDebtForwarded(address account, bool allowed) public {
        vm.prank(adapter);
        wrapper.admit(account, address(adapterFactory));
        subGate.setIsWhitelisted(wrapper.marketId(), false, account, allowed);
        subGate.setIsWhitelisted(wrapper.marketId(), true, account, !allowed);
        vm.expectCall(address(subGate), abi.encodeCall(IEnterSubGate.canIncreaseDebt, (wrapper.marketId(), account)));
        assertEq(wrapper.canIncreaseDebt(account), allowed);
    }

    function testDebtBubblesSubGateRevert() public {
        vm.prank(adapter);
        wrapper.admit(depositor, address(adapterFactory));
        vm.mockCallRevert(
            address(subGate),
            abi.encodeCall(IEnterSubGate.canIncreaseDebt, (wrapper.marketId(), depositor)),
            "gate reverted"
        );
        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseDebt(depositor);
    }

    function testSharedSubGateKeepsWhitelistsSeparate() public {
        VaultV2CompatibleEnterGate otherWrapper = new VaultV2CompatibleEnterGate(address(subGate), market);
        assertNotEq(wrapper.marketId(), otherWrapper.marketId());
        subGate.setIsWhitelisted(wrapper.marketId(), true, depositor, true);
        subGate.setIsWhitelisted(otherWrapper.marketId(), false, depositor, true);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertFalse(otherWrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.canIncreaseDebt(depositor));
        assertTrue(otherWrapper.canIncreaseDebt(depositor));
    }

    function testSharedSubGateKeepsAdmissionsAndFactoriesSeparate() public {
        VaultV2CompatibleEnterGate otherWrapper = new VaultV2CompatibleEnterGate(address(subGate), market);
        vm.mockCall(
            midnight, abi.encodeCall(IMidnight.liquidationLocked, (otherWrapper.marketId(), adapter)), abi.encode(false)
        );
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
        VaultV2CompatibleEnterGate otherWrapper = new VaultV2CompatibleEnterGate(address(subGate), market);
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
        VaultV2CompatibleEnterGate first = new VaultV2CompatibleEnterGate(openSubGate, market);
        VaultV2CompatibleEnterGate second = new VaultV2CompatibleEnterGate(openSubGate, market);
        assertEq(first.canIncreaseCredit(depositor), creditOpen);
        assertEq(second.canIncreaseCredit(depositor), creditOpen);
        assertEq(first.canIncreaseDebt(depositor), debtOpen);
        assertEq(second.canIncreaseDebt(depositor), debtOpen);
    }
}
