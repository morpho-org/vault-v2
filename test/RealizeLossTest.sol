// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

contract RealizeLossTest is BaseTest {
    AdapterMock internal adapter;
    bytes32[] internal ids;

    function setUp() public override {
        super.setUp();

        adapter = new AdapterMock(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(adapter), true));
        vault.setIsAdapter(address(adapter), true);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        ids = adapter.ids();
    }

    function testRealizeLossNotAdapter(address rdm) public {
        vm.assume(rdm != address(adapter));
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.realizeLoss(rdm, hex"");
    }

    function testRealizeLossNoRealizableLoss() public {
        adapter.setInterest(100);
        vm.expectRevert(ErrorsLib.NoRealizableLoss.selector);
        vault.realizeLoss(address(adapter), hex"");
    }

    function testRealizeLoss(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 0, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        vault.realizeLoss(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossThroughAllocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 0, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
        if (expectedLoss > 0) assertTrue(vault.enterBlocked(), "enter should be blocked");
    }

    function testRealizeLossThroughDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 0, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        vm.prank(allocator);
        vault.deallocate(address(adapter), hex"", 0);
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
        if (expectedLoss > 0) assertTrue(vault.enterBlocked(), "enter should be blocked");
    }

    function testRealizeLossThroughForceDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 0, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        vm.prank(allocator);
        vault.forceDeallocate(address(adapter), hex"", 0, address(this));
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
        if (expectedLoss > 0) assertTrue(vault.enterBlocked(), "enter should be blocked");
    }

    function testRealizeLossAllocationUpdate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 0, deposit);

        increaseAbsoluteCap("id-0", deposit);
        increaseAbsoluteCap("id-1", deposit);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(adapter), true));
        vault.setIsAdapter(address(adapter), true);
        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        for (uint256 i; i < ids.length; i++) {
            assertEq(vault.allocation(ids[i]), deposit, "allocation should be equal to the deposit");
        }

        adapter.setLoss(expectedLoss);

        vm.prank(allocator);
        vault.realizeLoss(address(adapter), hex"");
        for (uint256 i; i < ids.length; i++) {
            assertEq(vault.allocation(ids[i]), deposit - expectedLoss, "allocation should have decreased by the loss");
        }
    }
}
