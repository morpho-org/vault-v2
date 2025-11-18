// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";
import {EventsLib as MorphoEventsLib} from "../../lib/morpho-blue/src/libraries/EventsLib.sol";

contract MorphoMarketV1IntegrationBadDebtTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    uint256 internal constant INITIAL_DEPOSIT = 1.3e18;
    uint256 internal constant INITIAL_ON_MARKET1 = 1e18;
    uint256 internal constant INITIAL_ON_MARKET2 = 0.3e18;

    address internal immutable borrower = makeAddr("borrower");
    address internal immutable liquidator = makeAddr("liquidator");

    function setUp() public virtual override {
        super.setUp();

        assertEq(INITIAL_DEPOSIT, INITIAL_ON_MARKET1 + INITIAL_ON_MARKET2);

        vault.deposit(INITIAL_DEPOSIT, address(this));

        vm.startPrank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), INITIAL_ON_MARKET1);
        vault.allocate(address(adapter), abi.encode(marketParams2), INITIAL_ON_MARKET2);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), INITIAL_DEPOSIT);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), INITIAL_ON_MARKET1);
        assertEq(morpho.expectedSupplyAssets(marketParams2, address(adapter)), INITIAL_ON_MARKET2);
    }

    function testBadDebt() public {
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT);
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), INITIAL_DEPOSIT);

        // Create bad debt by liquidating everything on market 2.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        uint256 collateralOfBorrower = 3 * INITIAL_ON_MARKET2;
        morpho.supplyCollateral(marketParams2, collateralOfBorrower, borrower, hex"");
        morpho.borrow(marketParams2, INITIAL_ON_MARKET2, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), INITIAL_ON_MARKET1);

        oracle.setPrice(0);

        Id id = marketParams2.id();
        uint256 borrowerShares = morpho.position(id, borrower).borrowShares;
        vm.prank(liquidator);
        // Make sure that a bad debt of initialInMarket2 is created.
        vm.expectEmit();
        emit MorphoEventsLib.Liquidate(
            id, liquidator, borrower, 0, 0, collateralOfBorrower, INITIAL_ON_MARKET2, borrowerShares
        );
        morpho.liquidate(marketParams2, borrower, collateralOfBorrower, 0, hex"");

        assertEq(vault.totalAssets(), INITIAL_ON_MARKET1, "totalAssets() != INITIAL_ON_MARKET1");
        assertEq(
            vault.allocation(keccak256(expectedIdData1[2])), INITIAL_ON_MARKET1, "allocation(1) != INITIAL_ON_MARKET1"
        );
        assertEq(
            vault.allocation(keccak256(expectedIdData2[2])), INITIAL_ON_MARKET2, "allocation(2) != INITIAL_ON_MARKET2"
        );

        vault.accrueInterest();

        assertEq(vault._totalAssets(), INITIAL_ON_MARKET1, "_totalAssets() != INITIAL_ON_MARKET1");

        // Test update allocation.
        vault.forceDeallocate(address(adapter), abi.encode(marketParams2), 0, address(this));

        assertEq(vault.allocation(keccak256(expectedIdData2[2])), 0, "allocation(2) != 0");
    }
}
