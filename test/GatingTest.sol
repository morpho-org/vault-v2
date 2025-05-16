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
        vault.submit(abi.encodeCall(IVaultV2.setEnterGate, (gate)));
        vault.setEnterGate(gate);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setExitGate, (gate)));
        vault.setExitGate(gate);
    }

    function testNoGate() public {
        vault.deposit(0, address(this));
        vault.mint(0, address(this));
        vault.withdraw(0, address(this), address(this));
        vault.redeem(0, address(this), address(this));
    }

    function testCannotReceiveShares() public {
        setGate();
        vm.mockCall(
            gate, abi.encodeCall(IEnterGate.canReceiveShares, (sharesReceiver)), abi.encode(false)
        );
        vm.mockCall(gate, abi.encodeCall(IEnterGate.canSendAssets, (assetsSender)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotReceive.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCannotSendAssets() public {
        setGate();
        vm.mockCall(
            gate, abi.encodeCall(IEnterGate.canReceiveShares, (sharesReceiver)), abi.encode(true)
        );
        vm.mockCall(gate, abi.encodeCall(IEnterGate.canSendAssets, (assetsSender)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotSendAssets.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCannotSendShares() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(IExitGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(
            gate, abi.encodeCall(IExitGate.canReceiveAssets, (assetsReceiver)), abi.encode(true)
        );

        vm.expectRevert(ErrorsLib.CannotSend.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCannotReceiveAssets() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(IExitGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(
            gate, abi.encodeCall(IExitGate.canReceiveAssets, (assetsReceiver)), abi.encode(false)
        );

        vm.expectRevert(ErrorsLib.CannotReceiveAssets.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCanSendSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(IExitGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(
            gate, abi.encodeCall(IEnterGate.canReceiveShares, (sharesReceiver)), abi.encode(true)
        );

        vm.expectRevert(ErrorsLib.CannotSend.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanReceiveSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(IExitGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(
            gate, abi.encodeCall(IEnterGate.canReceiveShares, (sharesReceiver)), abi.encode(false)
        );

        vm.expectRevert(ErrorsLib.CannotReceive.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanSendSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(IExitGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(
            gate, abi.encodeCall(IEnterGate.canReceiveShares, (sharesReceiver)), abi.encode(true)
        );

        vm.expectRevert(ErrorsLib.CannotSend.selector);
        vm.prank(sharesSender);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }

    function testCanReceiveSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(IExitGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(
            gate, abi.encodeCall(IEnterGate.canReceiveShares, (sharesReceiver)), abi.encode(false)
        );

        vm.expectRevert(ErrorsLib.CannotReceive.selector);
        vm.prank(sharesReceiver);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }
}
