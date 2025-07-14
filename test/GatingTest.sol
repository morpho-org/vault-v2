// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract GatingTest is BaseTest {
    using MathLib for uint256;

    uint256 internal MAX_TEST_ASSETS;

    address gate;
    address sharesReceiver;
    address assetsSender;
    address sharesSender;
    address assetsReceiver;

    function setUp() public override {
        super.setUp();

        MAX_TEST_ASSETS = 10 ** min(18 + underlyingToken.decimals(), 36);

        gate = makeAddr("gate");

        sharesReceiver = makeAddr("sharesReceiver");
        assetsSender = makeAddr("assetsSender");
        sharesSender = makeAddr("sharesSender");
        assetsReceiver = makeAddr("assetsReceiver");
    }

    function setGate() internal {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSharesGate, (gate)));
        vault.setSharesGate(gate);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setReceiveAssetsGate, (gate)));
        vault.setReceiveAssetsGate(gate);
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
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(ISendAssetsGate.canSendAssets, (assetsSender)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotReceiveShares.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCannotSendAssets() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(ISendAssetsGate.canSendAssets, (assetsSender)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotSendAssets.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCannotSendShares() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (assetsReceiver)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotSendShares.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCannotReceiveAssets() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (assetsReceiver)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotReceiveAssets.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCanSendSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotSendShares.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanReceiveSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotReceiveShares.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanSendSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotSendShares.selector);
        vm.prank(sharesSender);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }

    function testCanReceiveSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotReceiveShares.selector);
        vm.prank(sharesReceiver);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }

    function testCanSendSharesPassthrough(bool hasGate, bool can) public {
        if (hasGate) {
            setGate();
            vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(can));
        }

        bool actualCan = vault.canSendShares(sharesSender);
        assertEq(actualCan, !hasGate || can);
    }

    function testCanReceiveSharesPassthrough(bool hasGate, bool can) public {
        if (hasGate) {
            setGate();
            vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesSender)), abi.encode(can));
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

    function testRealizeLossIncentiveGated(uint256 deposit, uint256 expectedLoss, bool canReceiveShares) public {
        address realizer = makeAddr("realizer");
        deposit = bound(deposit, 100, MAX_TEST_ASSETS);
        expectedLoss = bound(expectedLoss, 100, deposit);

        AdapterMock adapter = new AdapterMock(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        increaseAbsoluteCap(expectedIdData[0], type(uint128).max);
        increaseAbsoluteCap(expectedIdData[1], type(uint128).max);
        increaseRelativeCap(expectedIdData[0], WAD);
        increaseRelativeCap(expectedIdData[1], WAD);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setLoss(expectedLoss);

        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (realizer)), abi.encode(canReceiveShares));

        // Get expected incentive shares
        uint256 tentativeIncentive = expectedLoss * LOSS_REALIZATION_INCENTIVE_RATIO / WAD;
        uint256 assetsWithoutIncentive =
            vault.totalAssets().zeroFloorSub(expectedLoss).zeroFloorSub(tentativeIncentive) + 1;
        uint256 incentiveShares = tentativeIncentive * (vault.totalSupply() + VaultV2(address(vault)).virtualShares())
            / assetsWithoutIncentive;

        // Realize the loss.
        vm.prank(realizer);
        vault.realizeLoss(address(adapter), hex"");

        if (canReceiveShares) {
            assertEq(vault.balanceOf(realizer), incentiveShares);
        } else {
            assertEq(vault.balanceOf(realizer), 0);
        }
    }
}
