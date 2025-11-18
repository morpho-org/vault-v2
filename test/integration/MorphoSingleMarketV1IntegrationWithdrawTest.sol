// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoSingleMarketV1IntegrationTest.sol";

contract MorphoSingleMarketV1IntegrationWithdrawTest is MorphoSingleMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable receiver = makeAddr("receiver");
    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.2e18 - 1;
    uint256 internal initialInMarket = 0.3e18;
    uint256 internal initialTotal = 0.5e18 - 1;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialTotal, initialInIdle + initialInMarket);

        vault.deposit(initialTotal, address(this));

        vm.startPrank(allocator);
        vault.allocate(address(adapter), hex"", initialInMarket);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket);
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), initialInMarket);
    }

    function testWithdrawLessThanIdle(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vault.withdraw(assets, receiver, address(this));

        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket);
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), initialInMarket);
        assertEq(vault.allocation(keccak256(expectedIdData[0])), initialInMarket);
    }

    function testWithdrawMoreThanIdleNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, MAX_TEST_ASSETS);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawThanksToLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialInIdle + initialInMarket);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vault.withdraw(assets, receiver, address(this));

        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialTotal - assets);
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), initialInMarket + initialInIdle - assets);
        assertEq(vault.allocation(keccak256(expectedIdData[0])), initialInMarket - (assets - initialInIdle));
    }

    function testWithdrawTooMuchEvenWithLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + initialInMarket + 1, MAX_TEST_ASSETS);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawLiquidityAdapterNoLiquidity(uint256 assets) public {
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

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }
}
