// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

contract RealizeLossTest is BaseTest {
    AdapterMock internal adapter;

    function setUp() public override {
        super.setUp();

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

    function testRealizeLossNotAdapter(address notAdapter) public {
        vm.assume(notAdapter != address(adapter));
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.realizeLoss(notAdapter, hex"");
    }

    function testRealizeLossZero(uint256 deposit) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);

        vault.deposit(deposit, address(this));

        // Realize the loss.
        vault.realizeLoss(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit, "total assets should not have changed");
        assertEq(vault.enterBlocked(), false, "enter should not be blocked");
    }

    function testRealizeLossDirectly(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vault.realizeLoss(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
    }

    function testRealizeLossAllocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Account the loss.
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);

        // Realize the loss.
        vault.realizeLoss(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 1);
        adapter.setLoss(expectedLoss);

        // Account the loss.
        vm.prank(allocator);
        vault.deallocate(address(adapter), hex"", 0);

        // Realize the loss.
        vault.realizeLoss(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossForceDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 1);
        adapter.setLoss(expectedLoss);

        // Account the loss.
        vm.prank(allocator);
        vault.forceDeallocate(address(adapter), hex"", 0, address(this));

        // Realize the loss.
        vault.realizeLoss(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossAllocationUpdate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);
        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.realizeLoss(address(adapter), hex"");
        assertEq(
            vault.allocation(expectedIds[0]), deposit - expectedLoss, "allocation should have decreased by the loss"
        );
    }
}
