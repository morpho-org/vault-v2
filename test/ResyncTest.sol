// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract ResyncTest is BaseTest {
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

    function testResyncZero(uint256 deposit) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);

        vault.deposit(deposit, address(this));

        // Realize the loss.
        vault.resync();
        assertEq(vault.totalAssets(), deposit, "total assets should not have changed");
        assertEq(vault.enterBlocked(), false, "enter should not be blocked");
    }

    function testResync(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setTotalAssets(deposit - expectedLoss);

        // Realize the loss.
        uint256 sharesBefore = vault.balanceOf(address(this));
        vm.expectEmit(true, true, false, false);
        emit EventsLib.Resync(address(this), 0, 0);
        (uint256 incentiveShares, uint256 loss) = vault.resync();
        uint256 expectedShares = vault.balanceOf(address(this)) - sharesBefore;
        assertEq(incentiveShares, expectedShares, "incentive shares should be equal to expected shares");
        assertEq(loss, expectedLoss, "loss should be equal to expected loss");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
    }

    function testResyncAllocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setTotalAssets(deposit - expectedLoss);

        // Account the loss.
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);

        // Realize the loss.
        vault.resync();
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testResyncDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setTotalAssets(deposit - expectedLoss);

        // Account the loss.
        vm.prank(allocator);
        vault.deallocate(address(adapter), hex"", 0);

        // Realize the loss.
        vault.resync();
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testResyncForceDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setTotalAssets(deposit - expectedLoss);

        // Account the loss.
        vm.prank(allocator);
        vault.forceDeallocate(address(adapter), hex"", 0, address(this));

        // Realize the loss.
        vault.resync();
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testResyncAllocationUpdate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        adapter.setTotalAssets(deposit - expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.resync();
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
    }

    function testResyncAcrossAdaptersAndDiscoverBalance(
        uint256 deposit1,
        uint256 expectedLoss1,
        uint256 deposit2,
        uint256 expectedLoss2,
        uint256 discoveredBalance
    ) public {
        deposit1 = bound(deposit1, 1, MAX_TEST_AMOUNT);
        expectedLoss1 = bound(expectedLoss1, 1, deposit1);
        deposit2 = bound(deposit2, 1, MAX_TEST_AMOUNT);
        expectedLoss2 = bound(expectedLoss2, 1, deposit2);
        discoveredBalance = bound(discoveredBalance, 0, expectedLoss1 + expectedLoss2);

        AdapterMock adapter2 = new AdapterMock(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter2), true)));
        vault.setIsAdapter(address(adapter2), true);

        vault.deposit(deposit1, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit1);
        adapter.setTotalAssets(deposit1 - expectedLoss1);

        vault.deposit(deposit2, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter2), hex"", deposit2);
        adapter2.setTotalAssets(deposit2 - expectedLoss2);

        deal(address(underlyingToken), address(vault), discoveredBalance);

        // Realize the loss.
        vm.prank(allocator);
        vault.resync();
        assertEq(
            vault.totalAssets(),
            deposit1 - expectedLoss1 + deposit2 - expectedLoss2 + discoveredBalance,
            "incorrect total assets"
        );
    }
    // To test:
    // - resync across 2 adapters
    // - resync with donation in balance not yet accounting in total assets
}
