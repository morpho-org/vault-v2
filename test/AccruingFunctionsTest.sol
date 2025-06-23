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
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(vic))));
        vault.setVic(address(vic));

        increaseAbsoluteCap("id-0", WAD);
        increaseAbsoluteCap("id-1", WAD);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);

        deal(address(underlyingToken), address(vault), 1);
        vm.prank(address(vault));
        vault.allocate(address(adapter), hex"", 1);
    }

    function testAllocateAccruesInterest() public {
        skip(1);
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);
    }

    function testDeallocateAccruesInterest() public {
        skip(1);
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vm.prank(allocator);
        vault.deallocate(address(adapter), hex"", 0);
    }

    function testForceDeallocateAccruesInterest() public {
        skip(1);
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.forceDeallocate(address(adapter), hex"", 0, address(this));
    }

    function testRealizeAccruesInterest() public {
        skip(1);
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        bytes32[] memory ids = new bytes32[](0);
        vm.mockCall(address(adapter), abi.encodeCall(IAdapter.realizeLoss, (hex"")), abi.encode(ids, 1));
        vault.realizeLoss(address(adapter), hex"");
    }

    function testDepositAccruesInterest() public {
        skip(1);
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.deposit(0, address(this));
    }

    function testMintAccruesInterest() public {
        skip(1);
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.mint(0, address(this));
    }

    function testWithdrawAccruesInterest() public {
        skip(1);
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.withdraw(0, address(this), address(this));
    }

    function testRedeemAccruesInterest() public {
        skip(1);
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.redeem(0, address(this), address(this));
    }

    function testSetVicAccruesInterest() public {
        skip(1);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(vic))));
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.setVic(address(vic));
    }

    function testSetPerformanceFeeAccruesInterest() public {
        skip(1);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (0)));
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.setPerformanceFee(0);
    }

    function testSetManagementFeeAccruesInterest() public {
        skip(1);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (0)));
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.setManagementFee(0);
    }

    function testSetPerformanceFeeRecipientAccruesInterest() public {
        skip(1);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (address(0))));
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.setPerformanceFeeRecipient(address(0));
    }

    function testSetManagementFeeRecipientAccruesInterest() public {
        skip(1);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (address(0))));
        vm.expectCall(address(vic), bytes.concat(IVic.interestPerSecond.selector));
        vault.setManagementFeeRecipient(address(0));
    }
}
