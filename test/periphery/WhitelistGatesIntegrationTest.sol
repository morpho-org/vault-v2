// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "../BaseTest.sol";
import {WhitelistReceiveSharesGate} from "../../src/periphery/WhitelistReceiveSharesGate.sol";
import {WhitelistSendAssetsGate} from "../../src/periphery/WhitelistSendAssetsGate.sol";
import {ErrorsLib} from "../../src/libraries/ErrorsLib.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";

contract WhitelistGatesIntegrationTest is BaseTest {
    uint256 internal constant ASSETS = 1e18;

    WhitelistReceiveSharesGate internal receiveSharesGate;
    WhitelistSendAssetsGate internal sendAssetsGate;

    address internal roleSetter = makeAddr("roleSetter");
    address internal whitelister = makeAddr("whitelister");
    address internal depositor = makeAddr("depositor");
    address internal receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();

        receiveSharesGate = new WhitelistReceiveSharesGate(roleSetter);
        sendAssetsGate = new WhitelistSendAssetsGate(roleSetter);

        vm.startPrank(roleSetter);
        receiveSharesGate.setIsWhitelister(whitelister, true);
        sendAssetsGate.setIsWhitelister(whitelister, true);
        vm.stopPrank();

        deal(address(underlyingToken), depositor, ASSETS);
        vm.prank(depositor);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testWhitelistReceiveSharesGateControlsVaultDeposits() public {
        _setReceiveSharesGate(address(receiveSharesGate));

        vm.expectRevert(ErrorsLib.CannotReceiveShares.selector);
        vm.prank(depositor);
        vault.deposit(ASSETS, receiver);

        vm.prank(whitelister);
        receiveSharesGate.setIsWhitelisted(receiver, true);

        vm.prank(depositor);
        uint256 shares = vault.deposit(ASSETS, receiver);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(receiver), shares);
    }

    function testWhitelistSendAssetsGateControlsVaultDeposits() public {
        _setSendAssetsGate(address(sendAssetsGate));

        vm.expectRevert(ErrorsLib.CannotSendAssets.selector);
        vm.prank(depositor);
        vault.deposit(ASSETS, receiver);

        vm.prank(whitelister);
        sendAssetsGate.setIsWhitelisted(depositor, true);

        vm.prank(depositor);
        uint256 shares = vault.deposit(ASSETS, receiver);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(receiver), shares);
    }

    function _setReceiveSharesGate(address gate) internal {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setReceiveSharesGate, (gate)));
        vault.setReceiveSharesGate(gate);
    }

    function _setSendAssetsGate(address gate) internal {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSendAssetsGate, (gate)));
        vault.setSendAssetsGate(gate);
    }
}
