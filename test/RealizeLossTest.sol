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
        assertEq(
            AdapterMock(adapter).recordedSelector(),
            IVaultV2.realizeLoss.selector,
            "Selector incorrect after realizeLoss"
        );
        assertEq(AdapterMock(adapter).recordedSender(), address(this), "Sender incorrect after realizeLoss");
    }

    function testRealizeLoss(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        uint256 sharesBefore = vault.balanceOf(address(this));
        bytes32[] memory emptyIds = new bytes32[](0);
        vm.expectEmit(true, true, false, false);
        emit EventsLib.RealizeLoss(address(this), address(adapter), emptyIds, 0, 0);
        (uint256 incentiveShares, uint256 loss) = vault.realizeLoss(address(adapter), hex"");
        uint256 expectedShares = vault.balanceOf(address(this)) - sharesBefore;
        assertEq(incentiveShares, expectedShares, "incentive shares should be equal to expected shares");
        assertEq(loss, expectedLoss, "loss should be equal to expected loss");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
    }

    function testRealizeLossAllocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
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
        vault.allocate(address(adapter), hex"", deposit);
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
        vault.allocate(address(adapter), hex"", deposit);
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
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.realizeLoss(address(adapter), hex"");
        assertEq(
            vault.allocation(expectedIds[0]), deposit - expectedLoss, "allocation should have decreased by the loss"
        );
    }

    function testRealizeMoreThanTotalAssets(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, deposit + 1, (deposit + 1) * 2);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setInterest(expectedLoss - deposit);
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.realizeLoss(address(adapter), hex"");
        assertEq(vault.totalAssets(), 0, "total assets should be 0");
    }
}
