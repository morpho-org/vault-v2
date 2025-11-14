// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";
import {EventsLib as MorphoEventsLib} from "../../lib/morpho-blue/src/libraries/EventsLib.sol";

contract MorphoMarketV1IntegrationBadDebtTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    uint256 internal constant INITIAL_DEPOSIT = 1.3e18;

    address internal immutable borrower = makeAddr("borrower");
    address internal immutable liquidator = makeAddr("liquidator");

    function setUp() public virtual override {
        super.setUp();

        vault.deposit(INITIAL_DEPOSIT, address(this));

        vm.startPrank(allocator);
        vault.allocate(address(adapter), hex"", INITIAL_DEPOSIT);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), INITIAL_DEPOSIT);
        assertEq(morpho.expectedSupplyAssets(marketParams, address(adapter)), INITIAL_DEPOSIT);
    }

    function testBadDebt() public {
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT);
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), INITIAL_DEPOSIT);

        // Create bad debt by liquidating everything.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        uint256 collateralOfBorrower = 3 * INITIAL_DEPOSIT;
        morpho.supplyCollateral(marketParams, collateralOfBorrower, borrower, hex"");
        morpho.borrow(marketParams, INITIAL_DEPOSIT, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);

        oracle.setPrice(0);

        Id id = marketParams.id();
        uint256 borrowerShares = morpho.position(id, borrower).borrowShares;
        vm.prank(liquidator);
        // Make sure that a bad debt is created.
        vm.expectEmit();
        emit MorphoEventsLib.Liquidate(
            id, liquidator, borrower, 0, 0, collateralOfBorrower, INITIAL_DEPOSIT, borrowerShares
        );
        morpho.liquidate(marketParams, borrower, collateralOfBorrower, 0, hex"");

        assertEq(vault.totalAssets(), 0, "totalAssets() != 0");

        vault.accrueInterest();

        assertEq(vault._totalAssets(), 0, "_totalAssets() != 0");
    }
}
