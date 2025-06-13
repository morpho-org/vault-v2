// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract EmptyAdapter is IAdapter {
    bytes32[] ids = [keccak256("id")];

    function allocate(bytes memory, uint256) external view returns (bytes32[] memory, uint256) {
        return (ids, 0);
    }

    function deallocate(bytes memory, uint256) external view returns (bytes32[] memory, uint256) {
        return (ids, 0);
    }
}

contract AccrueInterestTest is BaseTest {
    EmptyAdapter adapter;

    function setUp() public override {
        super.setUp();

        adapter = new EmptyAdapter();

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(vic))));
        vault.setVic(address(vic));
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
