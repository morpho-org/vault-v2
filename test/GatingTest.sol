// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
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

        vm.expectRevert(ErrorsLib.CannotReceive.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCannotSendUnderlyingAssets() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(ISendAssetsGate.canSendAssets, (assetsSender)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotSendUnderlyingAssets.selector);
        vm.prank(assetsSender);
        vault.deposit(0, sharesReceiver);
    }

    function testCannotSendShares() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (assetsReceiver)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotSend.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCannotReceiveUnderlyingAssets() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (assetsReceiver)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotReceiveUnderlyingAssets.selector);
        vm.prank(sharesSender);
        vault.redeem(0, assetsReceiver, sharesSender);
    }

    function testCanSendSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotSend.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanReceiveSharesTransfer() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotReceive.selector);
        vm.prank(sharesSender);
        vault.transfer(sharesReceiver, 0);
    }

    function testCanSendSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(true));

        vm.expectRevert(ErrorsLib.CannotSend.selector);
        vm.prank(sharesSender);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }

    function testCanReceiveSharesTransferFrom() public {
        setGate();
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(true));
        vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesReceiver)), abi.encode(false));

        vm.expectRevert(ErrorsLib.CannotReceive.selector);
        vm.prank(sharesReceiver);
        vault.transferFrom(sharesSender, sharesReceiver, 0);
    }

    function testCanSendPassthrough(bool hasGate, bool can) public {
        if (hasGate) {
            setGate();
            vm.mockCall(gate, abi.encodeCall(ISharesGate.canSendShares, (sharesSender)), abi.encode(can));
        }

        bool actualCan = vault.canSend(sharesSender);
        assertEq(actualCan, !hasGate || can);
    }

    function testCanReceivePassthrough(bool hasGate, bool can) public {
        if (hasGate) {
            setGate();
            vm.mockCall(gate, abi.encodeCall(ISharesGate.canReceiveShares, (sharesSender)), abi.encode(can));
        }

        bool actualCan = vault.canReceive(sharesSender);
        assertEq(actualCan, !hasGate || can);
    }

    function testVaultCanAlwaysReceiveAssets() public {
        setGate();
        // Mock the gate to return false for all addresses
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (address(0x123))), abi.encode(false));
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (address(0x456))), abi.encode(false));
        
        // The vault should be able to receive assets even when the gate blocks other addresses
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (address(vault))), abi.encode(false));
        
        // This should not revert even though the gate returns false for the vault address
        // because the vault itself is always allowed to receive assets
        vault.deposit(100, address(this));
        vault.withdraw(50, address(vault), address(this));
    }

    function testForceDeallocateWithBlockedVault() public {
        setGate();
        // Mock the gate to return false for the vault address
        vm.mockCall(gate, abi.encodeCall(IReceiveAssetsGate.canReceiveAssets, (address(vault))), abi.encode(false));
        
        // Set up an adapter with a penalty
        address adapter = makeAddr("adapter");
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (adapter, true)));
        vault.setIsAdapter(adapter, true);
        
        uint256 penalty = 0.1e18; // 10% penalty
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (adapter, penalty)));
        vault.setForceDeallocatePenalty(adapter, penalty);
        
        // Deposit some assets
        vault.deposit(1000, address(this));
        
        // This should not revert even though the gate blocks the vault address
        // because the vault itself is always allowed to receive assets in forceDeallocate
        vault.forceDeallocate(adapter, hex"", 100, address(this));
    }
}
