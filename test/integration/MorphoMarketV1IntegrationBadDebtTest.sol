// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";
import {EventsLib as MorphoEventsLib} from "../../lib/morpho-blue/src/libraries/EventsLib.sol";

contract MorphoMarketV1IntegrationBadDebtTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    uint256 internal constant initialDeposit = 1.3e18;
    uint256 internal constant initialInMarket1 = 1e18;
    uint256 internal constant initialInMarket2 = 0.3e18;

    address internal immutable borrower = makeAddr("borrower");
    address internal immutable liquidator = makeAddr("liquidator");

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialDeposit, initialInMarket1 + initialInMarket2);

        vault.deposit(initialDeposit, address(this));

        vm.startPrank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), initialInMarket1);
        vault.allocate(address(adapter), abi.encode(marketParams2), initialInMarket2);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialDeposit);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), initialInMarket1);
        assertEq(morpho.expectedSupplyAssets(marketParams2, address(adapter)), initialInMarket2);
    }

    function testBadDebt() public {
        assertEq(vault.totalAssets(), initialDeposit);
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), initialDeposit);

        // Create bad debt by liquidating everything on market 2.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        uint256 collateralOfBorrower = 3 * initialInMarket2;
        morpho.supplyCollateral(marketParams2, collateralOfBorrower, borrower, hex"");
        morpho.borrow(marketParams2, initialInMarket2, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMarket1);

        oracle.setPrice(0);

        Id id = marketParams2.id();
        uint256 borrowerShares = morpho.position(id, borrower).borrowShares;
        vm.prank(liquidator);
        // Make sure that a bad debt of initialInMarket2 is created.
        vm.expectEmit();
        emit MorphoEventsLib.Liquidate(
            id, liquidator, borrower, 0, 0, collateralOfBorrower, initialInMarket2, borrowerShares
        );
        morpho.liquidate(marketParams2, borrower, collateralOfBorrower, 0, hex"");

        assertEq(vault.totalAssets(), initialInMarket1, "totalAssets() != initialInMarket1");
        assertEq(vault.allocation(keccak256(expectedIdData1[2])), initialInMarket1, "allocation(1) != initialInMarket1");
        assertEq(vault.allocation(keccak256(expectedIdData2[2])), initialInMarket2, "allocation(2) != initialInMarket2");

        vault.accrueInterest();

        assertEq(vault._totalAssets(), initialInMarket1, "_totalAssets() != initialInMarket1");

        // Test update allocation.
        vault.forceDeallocate(address(adapter), abi.encode(marketParams2), 0, address(this));

        assertEq(vault.allocation(keccak256(expectedIdData2[2])), 0, "allocation(2) != 0");
    }
}
