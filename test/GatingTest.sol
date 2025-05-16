// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract GatingTest is BaseTest {
    address gate;
    address sharesReceiver;
    address assetsSender;
    address sharesSender;
    address assetsReceiver;

    function setUp() public override {
        super.setUp();

        gate = makeAddr("gate");

        sharesReceiver = makeAddr("sharesReceiver");
        assetsSender = makeAddr("assetsSender");
        sharesSender = makeAddr("sharesSender");
        assetsReceiver = makeAddr("assetsReceiver");
    }

    function setGate() internal {
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setEnterGate.selector, gate));
        vault.setEnterGate(gate);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setExitGate.selector, gate));
        vault.setExitGate(gate);
    }

    function testNoGate() public {
        vault.deposit(0, address(this));
        vault.mint(0, address(this));
        vault.withdraw(0, address(this), address(this));
        vault.redeem(0, address(this), address(this));
    }

    function testCanReceiveShares() public {
        setGate();
        vm.mockCall(
            gate, abi.encodeWithSelector(IEnterGate.canReceiveShares.selector, sharesReceiver), abi.encode(false)
        );
        vm.mockCall(gate, abi.encodeWithSelector(IEnterGate.canSendAssets.selector, assetsSender), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotReceive.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCanSendAssets() public {
        setGate();
        vm.mockCall(
            gate, abi.encodeWithSelector(IEnterGate.canReceiveShares.selector, sharesReceiver), abi.encode(true)
        );
        vm.mockCall(gate, abi.encodeWithSelector(IEnterGate.canSendAssets.selector, assetsSender), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotSend.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCanSendShares() public {
        setGate();
        vm.mockCall(gate, abi.encodeWithSelector(IExitGate.canSendShares.selector, sharesSender), abi.encode(true));
        vm.mockCall(
            gate, abi.encodeWithSelector(IExitGate.canReceiveAssets.selector, assetsReceiver), abi.encode(false)
        );

        vm.expectRevert(ErrorsLib.CannotReceiveAssets.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCanReceiveAssets() public {
        setGate();
        vm.mockCall(gate, abi.encodeWithSelector(IExitGate.canSendShares.selector, sharesSender), abi.encode(true));
        vm.mockCall(
            gate, abi.encodeWithSelector(IExitGate.canReceiveAssets.selector, assetsReceiver), abi.encode(false)
        );

        vm.expectRevert(ErrorsLib.CannotSendAssets.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCanSendSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeWithSelector(IExitGate.canSendShares.selector, sharesSender), abi.encode(false));
        vm.mockCall(
            gate, abi.encodeWithSelector(IEnterGate.canReceiveShares.selector, sharesReceiver), abi.encode(true)
        );

        vm.expectRevert(ErrorsLib.CannotSend.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanReceiveSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeWithSelector(IExitGate.canSendShares.selector, sharesSender), abi.encode(true));
        vm.mockCall(
            gate, abi.encodeWithSelector(IEnterGate.canReceiveShares.selector, sharesReceiver), abi.encode(false)
        );

        vm.expectRevert(ErrorsLib.CannotReceive.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanSendSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeWithSelector(IExitGate.canSendShares.selector, sharesSender), abi.encode(false));
        vm.mockCall(
            gate, abi.encodeWithSelector(IEnterGate.canReceiveShares.selector, sharesReceiver), abi.encode(true)
        );

        vm.expectRevert(ErrorsLib.CannotSend.selector);
        vm.prank(sharesSender);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }

    function testCanReceiveSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeWithSelector(IExitGate.canSendShares.selector, sharesSender), abi.encode(true));
        vm.mockCall(
            gate, abi.encodeWithSelector(IEnterGate.canReceiveShares.selector, sharesReceiver), abi.encode(false)
        );

        vm.expectRevert(ErrorsLib.CannotReceive.selector);
        vm.prank(sharesReceiver);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }
}
