// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract Reverting {}

contract AccrueInterestTest is BaseTest {
    using MathLib for uint256;

    address performanceFeeRecipient = makeAddr("performanceFeeRecipient");
    address managementFeeRecipient = makeAddr("managementFeeRecipient");
    uint256 MAX_TEST_ASSETS;

    function setUp() public override {
        super.setUp();

        MAX_TEST_ASSETS = 10 ** min(18 + underlyingToken.decimals(), 36);

        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (performanceFeeRecipient)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (managementFeeRecipient)));
        vm.stopPrank();

        vault.setPerformanceFeeRecipient(performanceFeeRecipient);
        vault.setManagementFeeRecipient(managementFeeRecipient);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testAccrueInterestNoVic(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 10 * 365 days);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(0))));
        vault.setVic(address(0));

        uint256 totalAssetsBefore = vault.totalAssets();
        skip(elapsed);

        vault.accrueInterest();
        assertEq(vault.totalAssets(), totalAssetsBefore);
    }

    function testAccrueInterestView(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 elapsed
    ) public {
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        interestPerSecond = bound(interestPerSecond, 0, type(uint96).max);
        elapsed = bound(elapsed, 0, 10 * 365 days);

        // Setup.
        vm.prank(allocator);
        vic.setInterestPerSecondAndDeadline(interestPerSecond, type(uint64).max);
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));

        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Normal path.
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = vault.accrueInterestView();
        vault.accrueInterest();
        assertEq(newTotalAssets, vault.totalAssets());
        assertEq(performanceFeeShares, vault.balanceOf(performanceFeeRecipient));
        assertEq(managementFeeShares, vault.balanceOf(managementFeeRecipient));
    }

    function testAccrueInterest(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        interestPerSecond = bound(interestPerSecond, 0, type(uint96).max);
        elapsed = bound(elapsed, 1, 10 * 365 days);

        // Setup.
        vault.deposit(deposit, address(this));
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);
        vm.prank(allocator);
        vic.setInterestPerSecondAndDeadline(interestPerSecond, type(uint64).max);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Normal path.
        assertEq(vault._totalAssets(), deposit);
        uint256 interest = interestPerSecond * elapsed;
        uint256 totalAssets = deposit + interest;
        uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
        uint256 managementFeeAssets = (totalAssets * elapsed).mulDivDown(managementFee, WAD);
        uint256 performanceFeeShares = performanceFeeAssets.mulDivDown(
            vault.totalSupply() + vault.virtualShares(), totalAssets + 1 - performanceFeeAssets - managementFeeAssets
        );
        uint256 managementFeeShares = managementFeeAssets.mulDivDown(
            vault.totalSupply() + vault.virtualShares(), totalAssets + 1 - managementFeeAssets - performanceFeeAssets
        );
        vm.expectEmit();
        emit EventsLib.AccrueInterest(deposit, totalAssets, performanceFeeShares, managementFeeShares);
        vault.accrueInterest();
        assertEq(vault.totalAssets(), totalAssets);
        assertEq(vault.balanceOf(performanceFeeRecipient), performanceFeeShares);
        assertEq(vault.balanceOf(managementFeeRecipient), managementFeeShares);

        // Check no emit when reaccruing in same timestamp
        vm.recordLogs();
        vault.accrueInterest();
        assertEq(vm.getRecordedLogs().length, 0, "should not log");
    }

    function testAccrueInterestTooHigh(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        vm.assume(deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD) <= type(uint96).max);
        interestPerSecond = bound(interestPerSecond, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD), type(uint96).max);
        elapsed = bound(elapsed, 0, 20 * 365 days);

        // Setup.
        vault.deposit(deposit, address(this));
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Rate too high.
        vm.prank(allocator);
        vic.setInterestPerSecondAndDeadline(interestPerSecond, type(uint64).max);
        uint256 totalAssetsBefore = vault.totalAssets();
        vault.accrueInterest();
        assertEq(vault.totalAssets(), totalAssetsBefore);
    }

    function testAccrueInterestMaxRateValue() public {
        uint256 deposit = 1e18;

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vic.setInterestPerSecondAndDeadline(deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD), type(uint64).max);
        skip(365 days);

        vault.accrueInterest();
        assertApproxEqRel(vault.totalAssets(), deposit * 3, 0.00001e18);
    }

    function testSetVicWithNoCodeVic(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 1000 weeks);

        // Setup.
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(1))));
        vault.setVic(address(1));
        vm.warp(vm.getBlockTimestamp() + elapsed);

        vm.expectRevert();
        vault.accrueInterest();

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(42))));
        vault.setVic(address(42));
    }

    function testSetVicWithRevertingVic(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 1000 weeks);

        address reverting = address(new Reverting());

        // Setup.
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (reverting)));
        vault.setVic(reverting);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        vm.expectRevert();
        vault.accrueInterest();

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(42))));
        vault.setVic(address(42));

        // Check lastUpdate updated
        assertEq(vault.lastUpdate(), vm.getBlockTimestamp());
    }

    function testAccrueInterestFees(
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 deposit,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        interestPerSecond = bound(interestPerSecond, 0, type(uint96).max);
        elapsed = bound(elapsed, 0, 10 * 365 days);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.setPerformanceFee(performanceFee);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));
        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(allocator);
        vic.setInterestPerSecondAndDeadline(interestPerSecond, type(uint64).max);

        vm.warp(block.timestamp + elapsed);

        uint256 interest = interestPerSecond * elapsed;
        uint256 newTotalAssets = totalAssetsBefore + interest;
        uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
        uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDivDown(managementFee, WAD);

        vault.accrueInterest();

        // Share price can be relatively high in the conditions of this test, making rounding errors more significant.
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(managementFeeRecipient)), managementFeeAssets, 100);
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(performanceFeeRecipient)), performanceFeeAssets, 100);
    }
}
