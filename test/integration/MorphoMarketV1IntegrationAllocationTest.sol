// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";

contract MorphoMarketV1IntegrationAllocationTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.3e18;
    uint256 internal initialInMarket = 0.7e18;
    uint256 internal initialTotal = 1e18;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialTotal, initialInIdle + initialInMarket);

        vault.deposit(initialTotal, address(this));

        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams), initialInMarket);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket);
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), initialInMarket);
        assertEq(vault.allocation(keccak256(expectedIdData[0])), initialInMarket);
    }

    function testDeallocateLessThanAllocated(uint256 assets) public {
        assets = bound(assets, 0, initialInMarket);

        vm.prank(allocator);
        vault.deallocate(address(adapter), abi.encode(marketParams), assets);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle + assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket - assets);
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), initialInMarket - assets);
        assertEq(vault.allocation(keccak256(expectedIdData[0])), initialInMarket - assets);
    }

    function testDeallocateMoreThanAllocated(uint256 assets) public {
        assets = bound(assets, initialInMarket + 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vm.expectRevert();
        vault.deallocate(address(adapter), abi.encode(marketParams), assets);
    }

    function testDeallocateNoLiquidity(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams, 2 * initialInMarket, borrower, hex"");
        morpho.borrow(marketParams, initialInMarket, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);

        vm.prank(allocator);
        vm.expectRevert();
        vault.deallocate(address(adapter), abi.encode(marketParams), assets);
    }

    function testAllocateLessThanIdleToMarket1(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams), assets);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket + assets);
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), initialInMarket + assets);
        assertEq(vault.allocation(keccak256(expectedIdData[0])), initialInMarket + assets);
    }

    function testAllocateMoreThanIdle(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.TransferReverted.selector);
        vault.allocate(address(adapter), abi.encode(marketParams), assets);
    }
}
