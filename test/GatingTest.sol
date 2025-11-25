// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract GatingTest is BaseTest {
    using MathLib for uint256;

    uint256 internal maxTestAssets;

    address gate;
    address sharesReceiver;
    address assetsSender;
    address sharesSender;
    address assetsReceiver;

    function setUp() public override {
        super.setUp();

        maxTestAssets = 10 ** min(18 + underlyingToken.decimals(), 36);

        gate = makeAddr("gate");

        sharesReceiver = makeAddr("sharesReceiver");
        assetsSender = makeAddr("assetsSender");
        sharesSender = makeAddr("sharesSender");
        assetsReceiver = makeAddr("assetsReceiver");
    }

    function setGate() internal {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setReceiveSharesGate, (gate)));
        vault.setReceiveSharesGate(gate);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setReceiveAssetsGate, (gate)));
        vault.setReceiveAssetsGate(gate);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSendSharesGate, (gate)));
        vault.setSendSharesGate(gate);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSendAssetsGate, (gate)));
        vault.setSendAssetsGate(gate);
    }

    function testNoGate() public {
        vault.deposit(0, address(this));
        vault.mint(0, address(this));
        vault.withdraw(0, address(this), address(this));
        vault.redeem(0, address(this), address(this));
    }

    function testCannotReceiveShares() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(IReceiveSharesGate.canReceiveShares, (sharesReceiver)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(ISendAssetsGate.canSendAssets, (assetsSender)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotReceiveShares.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCannotSendAssets() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(IReceiveSharesGate.canReceiveShares, (sharesReceiver)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(ISendAssetsGate.canSendAssets, (assetsSender)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotSendAssets.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCannotSendShares() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISendSharesGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (assetsReceiver)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotSendShares.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCannotReceiveAssets() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISendSharesGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (assetsReceiver)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotReceiveAssets.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCanSendSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISendSharesGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(IReceiveSharesGate.canReceiveShares, (sharesReceiver)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotSendShares.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanReceiveSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISendSharesGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(IReceiveSharesGate.canReceiveShares, (sharesReceiver)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotReceiveShares.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanSendSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISendSharesGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(IReceiveSharesGate.canReceiveShares, (sharesReceiver)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotSendShares.selector);
        vm.prank(sharesSender);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }

    function testCanReceiveSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISendSharesGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(IReceiveSharesGate.canReceiveShares, (sharesReceiver)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotReceiveShares.selector);
        vm.prank(sharesReceiver);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }

    function testCanSendSharesPassthrough(bool hasGate, bool can) public {
        if (hasGate) {
            setGate();
            vm.mockCall(gate, abi.encodeCall(ISendSharesGate.canSendShares, (sharesSender)), abi.encode(can));
        }

        bool actualCan = vault.canSendShares(sharesSender);
        assertEq(actualCan, !hasGate || can);
    }

    function testCanReceiveSharesPassthrough(bool hasGate, bool can) public {
        if (hasGate) {
            setGate();
            vm.mockCall(gate, abi.encodeCall(IReceiveSharesGate.canReceiveShares, (sharesSender)), abi.encode(can));
        }

        bool actualCan = vault.canReceiveShares(sharesSender);
        assertEq(actualCan, !hasGate || can);
    }

    function testCanSendAssetsPassthrough(bool hasGate, bool can) public {
        if (hasGate) {
            setGate();
            vm.mockCall(gate, abi.encodeCall(ISendAssetsGate.canSendAssets, (assetsSender)), abi.encode(can));
        }

        bool actualCan = vault.canSendAssets(assetsSender);
        assertEq(actualCan, !hasGate || can);
    }

    function testCanReceiveAssetsPassthrough(bool hasGate, bool can) public {
        if (hasGate) {
            setGate();
            vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (assetsSender)), abi.encode(can));
        }

        bool actualCan = vault.canReceiveAssets(assetsSender);
        assertEq(actualCan, !hasGate || can);
    }
}
