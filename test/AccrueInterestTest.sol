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
    AdapterMock adapter;

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

        adapter = new AdapterMock(address(vault));
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setMaxRate, (MAX_MAX_RATE)));
        vault.setMaxRate(MAX_MAX_RATE);

        increaseAbsoluteCap("id-0", type(uint128).max);
        increaseAbsoluteCap("id-1", type(uint128).max);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");
    }

    /// forge-config: default.isolate = true
    function testAccrueInterestView(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interest,
        uint256 elapsed
    ) public {
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        elapsed = bound(elapsed, 0, 10 * 365 days);
        interest = bound(interest, 0, MAX_TEST_ASSETS);

        // Setup.
        vm.prank(allocator);
        adapter.setInterest(interest);
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));

        skip(elapsed);

        // Normal path.
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = vault.accrueInterestView();
        vault.accrueInterest();
        assertEq(newTotalAssets, vault._totalAssets());
        assertEq(performanceFeeShares, vault.balanceOf(performanceFeeRecipient));
        assertEq(managementFeeShares, vault.balanceOf(managementFeeRecipient));
    }

    /// forge-config: default.isolate = true
    function testTotalAssets(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interest,
        uint256 elapsed
    ) public {
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        elapsed = bound(elapsed, 0, 10 * 365 days);
        interest = bound(interest, 0, MAX_TEST_ASSETS);

        // Setup.
        vm.prank(allocator);
        adapter.setInterest(interest);
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));

        skip(elapsed);

        // Normal path.
        uint256 newTotalAssets = vault.totalAssets();
        vault.accrueInterest();
        assertEq(newTotalAssets, vault._totalAssets());
    }

    /// forge-config: default.isolate = true
    function testAccrueInterest(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interest,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 10 * 365 days);
        interest = bound(interest, 0, (deposit * MAX_MAX_RATE).mulDivDown(elapsed, WAD));

        // Setup.
        vault.deposit(deposit, address(this));
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);
        assertEq(adapter.realAssets(), deposit, "realAssetsBefore");
        vm.prank(allocator);
        adapter.setInterest(interest);
        skip(elapsed);

        // Normal path.
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
        assertEq(vault.totalAssets(), totalAssets, "totalAssets");
        assertEq(vault.balanceOf(performanceFeeRecipient), performanceFeeShares, "performanceFeeShares");
        assertEq(vault.balanceOf(managementFeeRecipient), managementFeeShares, "managementFeeShares");
    }

    /// forge-config: default.isolate = true
    function testAccrueInterestMaxRate(uint256 deposit, uint256 interest, uint256 elapsed) public {
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_MAX_RATE);
        elapsed = bound(elapsed, 0, 10 * 365 days);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setMaxRate, (MAX_MAX_RATE)));
        vault.setMaxRate(MAX_MAX_RATE);

        vault.deposit(deposit, address(this));

        vm.prank(allocator);
        adapter.setInterest(interest);
        skip(elapsed);

        vault.accrueInterest();

        assertLe(vault.totalAssets(), deposit + (deposit * elapsed).mulDivDown(MAX_MAX_RATE, WAD));
    }

    /// forge-config: default.isolate = true
    function testAccrueInterestFees(
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interest,
        uint256 deposit,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 0, 10 * 365 days);
        interest = bound(interest, 0, (deposit * MAX_MAX_RATE).mulDivDown(elapsed, WAD));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.setPerformanceFee(performanceFee);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));

        vm.prank(allocator);
        adapter.setInterest(interest);

        skip(elapsed);

        uint256 newTotalAssets = deposit + interest;
        uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
        uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDivDown(managementFee, WAD);

        vault.accrueInterest();

        // Share price can be relatively high in the conditions of this test, making rounding errors more significant.
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(managementFeeRecipient)), managementFeeAssets, 100);
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(performanceFeeRecipient)), performanceFeeAssets, 100);
    }
}
