// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";

contract MorphoMarketV1IntegrationAllocationTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.3e18;
    uint256 internal initialInMarket1 = 0.7e18;
    uint256 internal initialTotal = 1e18;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialTotal, initialInIdle + initialInMarket1);

        vault.deposit(initialTotal, address(this));

        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), initialInMarket1);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket1);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), initialInMarket1);
        assertEq(vault.allocation(keccak256(expectedIdData1[2])), initialInMarket1);
        assertEq(vault.allocation(keccak256(expectedIdData2[2])), 0);
    }

    function testDeallocateLessThanAllocated(uint256 assets) public {
        assets = bound(assets, 0, initialInMarket1);

        vm.prank(allocator);
        vault.deallocate(address(adapter), abi.encode(marketParams1), assets);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle + assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket1 - assets);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), initialInMarket1 - assets);
        assertEq(vault.allocation(keccak256(expectedIdData1[2])), initialInMarket1 - assets);
    }

    function testDeallocateMoreThanAllocated(uint256 assets) public {
        assets = bound(assets, initialInMarket1 + 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vm.expectRevert();
        vault.deallocate(address(adapter), abi.encode(marketParams1), assets);
    }

    function testDeallocateNoLiquidity(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams1, 2 * initialInMarket1, borrower, hex"");
        morpho.borrow(marketParams1, initialInMarket1, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);

        vm.prank(allocator);
        vm.expectRevert();
        vault.deallocate(address(adapter), abi.encode(marketParams1), assets);
    }

    function testAllocateLessThanIdleToMarket1(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), assets);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket1 + assets);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), initialInMarket1 + assets);
        assertEq(vault.allocation(keccak256(expectedIdData1[2])), initialInMarket1 + assets);
        assertEq(vault.allocation(keccak256(expectedIdData2[2])), 0);
    }

    function testAllocateLessThanIdleToMarket2(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams2), assets);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket1 + assets);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), initialInMarket1);
        assertEq(morpho.expectedSupplyAssets(marketParams2, address(adapter)), assets);
        assertEq(vault.allocation(keccak256(expectedIdData1[2])), initialInMarket1);
        assertEq(vault.allocation(keccak256(expectedIdData2[2])), assets);
    }

    function testAllocateMoreThanIdle(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.TransferReverted.selector);
        vault.allocate(address(adapter), abi.encode(marketParams1), assets);
    }

    function testAllocateNoDuplicateMarket() public {
        deal(address(underlyingToken), allocator, initialInMarket1);

        assertEq(adapter.marketParamsListLength(), 1, "incorrectly set up market list");

        oracle.setPrice(1e36);

        // Full borrow, extra collateralized.
        uint256 collateralAmount = 2 * initialInMarket1;
        deal(address(collateralToken), borrower, collateralAmount);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams1, collateralAmount, borrower, hex"");
        morpho.borrow(marketParams1, initialInMarket1, 0, borrower, borrower);
        vm.stopPrank();

        // Full loss.
        oracle.setPrice(0);
        morpho.liquidate(marketParams1, borrower, collateralAmount, 0, hex"");

        deal(address(underlyingToken), allocator, 1);

        // Update allocation to 0.
        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), 0);

        // Update allocation to 1.
        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), 1);

        assertEq(adapter.marketParamsListLength(), 1, "duplicate market in market list");
    }
}
