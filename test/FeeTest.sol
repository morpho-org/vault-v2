// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract FeeTest is BaseTest {
    using MathLib for uint256;

    address performanceFeeRecipient = makeAddr("performanceFeeRecipient");
    address managementFeeRecipient = makeAddr("managementFeeRecipient");
    uint256 constant MAX_DEPOSIT = 1e18 ether;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, performanceFeeRecipient));
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, managementFeeRecipient));
        vm.stopPrank();

        vault.setPerformanceFeeRecipient(performanceFeeRecipient);
        vault.setManagementFeeRecipient(managementFeeRecipient);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testPerformanceFeeWithoutManagementFee(
        uint256 performanceFee,
        uint256 rate,
        uint256 deposit,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        deposit = bound(deposit, 0, MAX_DEPOSIT);
        rate = bound(rate, 0, MAX_RATE_PER_SECOND);
        elapsed = bound(elapsed, 0, 1000 weeks);

        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, performanceFee));
        vault.setPerformanceFee(performanceFee);

        vault.deposit(deposit, address(this));

        vm.prank(manager);
        irm.setRate(rate);

        vm.warp(block.timestamp + elapsed);

        uint256 interest = vault.totalAssets().mulDivDown(rate.wTaylorCompounded(elapsed), WAD);
        uint256 newTotalAssets = vault.totalAssets() + interest;
        uint256 performanceFeeAssets =
            interest - interest.mulDivUp(WAD, WAD + performanceFee.wTaylorCompounded(elapsed));
        uint256 expectedShares =
            performanceFeeAssets.mulDivDown(vault.totalSupply() + 1, newTotalAssets + 1 - performanceFeeAssets);

        vault.accrueInterest();

        assertEq(vault.balanceOf(performanceFeeRecipient), expectedShares);
    }

    function testManagementFeeWithoutPerformanceFee(
        uint256 managementFee,
        uint256 rate,
        uint256 deposit,
        uint256 elapsed
    ) public {
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_DEPOSIT);
        rate = bound(rate, 0, MAX_RATE_PER_SECOND);
        elapsed = bound(elapsed, 0, 20 * 365 days);

        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, managementFee));
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));

        vm.prank(manager);
        irm.setRate(rate);

        vm.warp(block.timestamp + elapsed);

        uint256 interest = vault.totalAssets().mulDivDown(rate.wTaylorCompounded(elapsed), WAD);
        uint256 newTotalAssets = vault.totalAssets() + interest;
        uint256 managementFeeAssets =
            newTotalAssets - newTotalAssets.mulDivUp(WAD, WAD + managementFee.wTaylorCompounded(elapsed));
        uint256 expectedShares =
            managementFeeAssets.mulDivDown(vault.totalSupply() + 1, newTotalAssets + 1 - managementFeeAssets);

        vault.accrueInterest();

        assertEq(vault.balanceOf(managementFeeRecipient), expectedShares);
    }
}
