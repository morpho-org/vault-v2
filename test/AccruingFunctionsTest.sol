// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract AccruingFunctionsTest is BaseTest {
    AdapterMock adapter;

    function setUp() public override {
        super.setUp();

        adapter = new AdapterMock(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));

        increaseAbsoluteCap("id-0", type(uint128).max);
        increaseAbsoluteCap("id-1", type(uint128).max);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);

        deal(address(underlyingToken), address(vault), 1);
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 1);
    }

    function testAllocateAccruesInterest() public {
        skip(1);
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);
    }

    function testForceDeallocateAccruesInterest() public {
        skip(1);
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vault.forceDeallocate(address(adapter), hex"", 0, address(this));
    }

    function testDepositAccruesInterest() public {
        skip(1);
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vault.deposit(0, address(this));
    }

    function testMintAccruesInterest() public {
        skip(1);
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vault.mint(0, address(this));
    }

    function testWithdrawAccruesInterest() public {
        skip(1);
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vault.withdraw(0, address(this), address(this));
    }

    function testRedeemAccruesInterest() public {
        skip(1);
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vault.redeem(0, address(this), address(this));
    }

    function testSetPerformanceFeeAccruesInterest() public {
        skip(1);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (0)));
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vault.setPerformanceFee(0);
    }

    function testSetManagementFeeAccruesInterest() public {
        skip(1);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (0)));
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vault.setManagementFee(0);
    }

    function testSetPerformanceFeeRecipientAccruesInterest() public {
        skip(1);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (address(0))));
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vault.setPerformanceFeeRecipient(address(0));
    }

    function testSetManagementFeeRecipientAccruesInterest() public {
        skip(1);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (address(0))));
        vm.expectEmit(false, false, false, false);
        emit EventsLib.AccrueInterest(0, 0, 0, 0);
        vault.setManagementFeeRecipient(address(0));
    }

    function testSetMaxRateAccruesInterest() public {
        skip(1);
        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);
        assertEq(vault.lastUpdate(), block.timestamp);
    }
}
