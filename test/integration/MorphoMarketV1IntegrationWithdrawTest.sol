// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";

contract MorphoMarketV1IntegrationWithdrawTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable receiver = makeAddr("receiver");
    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.2e18 - 1;
    uint256 internal initialInMarket1 = 0.3e18;
    uint256 internal initialInMarket2 = 0.5e18;
    uint256 internal initialTotal = 1e18 - 1;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialTotal, initialInIdle + initialInMarket1 + initialInMarket2);

        vault.deposit(initialTotal, address(this));

        vm.startPrank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), initialInMarket1);
        vault.allocate(address(adapter), abi.encode(marketParams2), initialInMarket2);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket1 + initialInMarket2);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), initialInMarket1);
        assertEq(morpho.expectedSupplyAssets(marketParams2, address(adapter)), initialInMarket2);
    }

    function testWithdrawLessThanIdle(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vault.withdraw(assets, receiver, address(this));

        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket1 + initialInMarket2);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), initialInMarket1);
        assertEq(morpho.expectedSupplyAssets(marketParams2, address(adapter)), initialInMarket2);
        assertEq(vault.allocation(keccak256(expectedIdData1[2])), initialInMarket1);
        assertEq(vault.allocation(keccak256(expectedIdData2[2])), initialInMarket2);
    }

    function testWithdrawMoreThanIdleNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, MAX_TEST_ASSETS);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawThanksToLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialInIdle + initialInMarket1);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), abi.encode(marketParams1));

        vault.withdraw(assets, receiver, address(this));

        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialTotal - assets);
        assertEq(
            morpho.expectedSupplyAssets(marketParams1, address(adapter)), initialInMarket1 + initialInIdle - assets
        );
        assertEq(morpho.expectedSupplyAssets(marketParams2, address(adapter)), initialInMarket2);
        assertEq(vault.allocation(keccak256(expectedIdData1[2])), initialInMarket1 - (assets - initialInIdle));
        assertEq(vault.allocation(keccak256(expectedIdData2[2])), initialInMarket2);
    }

    function testWithdrawTooMuchEvenWithLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + initialInMarket1 + 1, MAX_TEST_ASSETS);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), abi.encode(marketParams1));

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawLiquidityAdapterNoLiquidity(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), abi.encode(marketParams1));

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams1, 2 * initialInMarket1, borrower, hex"");
        morpho.borrow(marketParams1, initialInMarket1, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket2);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }
}
