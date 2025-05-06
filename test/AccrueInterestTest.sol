// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract AccrueInterestTest is BaseTest {
    using MathLib for uint256;

    address performanceFeeRecipient = makeAddr("performanceFeeRecipient");
    address managementFeeRecipient = makeAddr("managementFeeRecipient");
    uint256 constant MAX_DEPOSIT = 1e18 ether;

    function setUp() public override {
        super.setUp();

        vm.startPrank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, performanceFeeRecipient));
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, managementFeeRecipient));
        vm.stopPrank();

        vault.setPerformanceFeeRecipient(performanceFeeRecipient);
        vault.setManagementFeeRecipient(managementFeeRecipient);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testTotalAssets(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 elapsed
    ) public {
        deposit = bound(deposit, 0, MAX_DEPOSIT);
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        elapsed = bound(elapsed, 0, 20 * 365 days);

        // Setup.
        vm.prank(manager);
        interestController.setInterestPerSecond(interestPerSecond);
        vm.startPrank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, performanceFee));
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, managementFee));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);
        vault.deposit(deposit, address(this));
        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Normal path.
        uint256 newTotalAssets = vault.totalAssets();
        vault.accrueInterest();
        assertEq(newTotalAssets, vault.lastTotalAssets());
    }

    function testAccrueInterestView(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 elapsed
    ) public {
        deposit = bound(deposit, 0, MAX_DEPOSIT);
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        elapsed = bound(elapsed, 0, 20 * 365 days);

        // Setup.
        vm.prank(manager);
        interestController.setInterestPerSecond(interestPerSecond);
        vm.startPrank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, performanceFee));
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, managementFee));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));

        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Normal path.
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = vault.accrueInterestView();
        vault.accrueInterest();
        assertEq(newTotalAssets, vault.lastTotalAssets());
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
        deposit = bound(deposit, 0, MAX_DEPOSIT);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        elapsed = bound(elapsed, 1, 20 * 365 days);

        // Setup.
        vault.deposit(deposit, address(this));
        vm.startPrank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, performanceFee));
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, managementFee));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Rate too high.
        vm.prank(manager);
        interestController.setInterestPerSecond(deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD) + 1);
        vm.expectRevert(ErrorsLib.InvalidRate.selector);
        vault.accrueInterest();

        // Normal path.
        vm.prank(manager);
        interestController.setInterestPerSecond(interestPerSecond);
        uint256 interest = interestPerSecond * elapsed;
        uint256 totalAssets = deposit + interest;
        uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
        uint256 performanceFeeShares =
            performanceFeeAssets.mulDivDown(vault.totalSupply() + 1, totalAssets + 1 - performanceFeeAssets);
        uint256 managementFeeAssets = (totalAssets * elapsed).mulDivDown(managementFee, WAD);
        uint256 managementFeeShares = managementFeeAssets.mulDivDown(
            vault.totalSupply() + 1 + performanceFeeShares, totalAssets + 1 - managementFeeAssets
        );
        vm.expectEmit();
        emit EventsLib.AccrueInterest(totalAssets, performanceFeeShares, managementFeeShares);
        vault.accrueInterest();
        assertEq(vault.lastTotalAssets(), totalAssets);
        assertEq(vault.balanceOf(performanceFeeRecipient), performanceFeeShares);
        assertEq(vault.balanceOf(managementFeeRecipient), managementFeeShares);
    }

    function testPerformanceFeeWithoutManagementFee(
        uint256 performanceFee,
        uint256 interestPerSecond,
        uint256 deposit,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        deposit = bound(deposit, 0, MAX_DEPOSIT);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        elapsed = bound(elapsed, 0, 1000 weeks);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, performanceFee));
        vault.setPerformanceFee(performanceFee);

        vault.deposit(deposit, address(this));

        vm.prank(manager);
        interestController.setInterestPerSecond(interestPerSecond);

        vm.warp(block.timestamp + elapsed);

        uint256 interest = interestPerSecond * elapsed;
        uint256 newTotalAssets = vault.lastTotalAssets() + interest;
        uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
        uint256 expectedShares =
            performanceFeeAssets.mulDivDown(vault.totalSupply() + 1, newTotalAssets + 1 - performanceFeeAssets);

        vault.accrueInterest();

        assertEq(vault.balanceOf(performanceFeeRecipient), expectedShares);
    }

    function testManagementFeeWithoutPerformanceFee(
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 deposit,
        uint256 elapsed
    ) public {
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_DEPOSIT);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        elapsed = bound(elapsed, 0, 20 * 365 days);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, managementFee));
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));

        vm.prank(manager);
        interestController.setInterestPerSecond(interestPerSecond);

        vm.warp(block.timestamp + elapsed);

        uint256 interest = interestPerSecond * elapsed;
        uint256 newTotalAssets = vault.lastTotalAssets() + interest;
        uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDivDown(managementFee, WAD);
        uint256 expectedShares =
            managementFeeAssets.mulDivDown(vault.totalSupply() + 1, newTotalAssets + 1 - managementFeeAssets);

        vault.accrueInterest();

        assertEq(vault.balanceOf(managementFeeRecipient), expectedShares);
    }
}
