// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract RealizeLossTest is BaseTest {
    AdapterMock internal adapter;
    uint256 MAX_TEST_AMOUNT;

    function setUp() public override {
        super.setUp();

        MAX_TEST_AMOUNT = 10 ** min(18 + underlyingToken.decimals(), 36);

        adapter = new AdapterMock(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        increaseAbsoluteCap(expectedIdData[0], type(uint128).max);
        increaseAbsoluteCap(expectedIdData[1], type(uint128).max);
        increaseRelativeCap(expectedIdData[0], WAD);
        increaseRelativeCap(expectedIdData[1], WAD);
    }

    function testRealizeLoss(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.expectEmit();
        emit EventsLib.AccrueInterest(deposit, deposit - expectedLoss, 0, 0);
        vault.accrueInterest();
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
        assertEq(vault.enterBlocked(), true, "enterBlocked should be true");

        // Try to deposit.
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.EnterBlocked.selector));
        vault.deposit(deposit, address(this));

        // Try to mint.
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.EnterBlocked.selector));
        vault.mint(deposit, address(this));
    }

    function testRealizeLossWithDepositNotFirstInteractionLossBefore(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);

        adapter.setLoss(expectedLoss);
        vault.accrueInterest();

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.EnterBlocked.selector));
        vault.deposit(deposit, address(this));
    }

    function testRealizeLossWithDepositNotFirstInteractionLossBetween(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);

        vault.accrueInterest();
        adapter.setLoss(expectedLoss);

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.EnterBlocked.selector));
        vault.deposit(deposit, address(this));
    }

    /// forge-config: default.isolate = true
    function testRealizeLossWithDepositFirstInteraction(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setLoss(expectedLoss);

        vault.deposit(deposit, address(this));
        assertEq(vault.totalAssets(), 2 * deposit - expectedLoss, "total assets should have decreased by the loss");
    }

    function testAllocationLossAllocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0); // TODO: with an amount.
        assertEq(
            vault.allocation(expectedIds[0]), deposit - expectedLoss, "allocation should have decreased by the loss"
        );
    }

    function testAllocationLossDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.deallocate(address(adapter), hex"", 0); // TODO: with an amount.
        assertEq(
            vault.allocation(expectedIds[0]), deposit - expectedLoss, "allocation should have decreased by the loss"
        );
    }

    function testAllocationLossForceDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vault.forceDeallocate(address(adapter), hex"", 0, address(this)); // TODO: with an amount.
        assertEq(
            vault.allocation(expectedIds[0]), deposit - expectedLoss, "allocation should have decreased by the loss"
        );
    }
}
