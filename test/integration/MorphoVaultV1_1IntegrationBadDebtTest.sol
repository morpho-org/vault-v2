// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1_1IntegrationTest.sol";
import {EventsLib as MorphoEventsLib} from "../../lib/metamorpho-v1.1/lib/morpho-blue/src/libraries/EventsLib.sol";

contract MorphoVaultV1_1IntegrationBadDebtTest is MorphoVaultV1_1IntegrationTest {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    uint256 internal constant initialDeposit = 1.3e18;
    uint256 internal constant initialOnMarket0 = 1e18;
    uint256 internal constant initialOnMarket1 = 0.3e18;

    address internal immutable borrower = makeAddr("borrower");
    address internal immutable liquidator = makeAddr("liquidator");

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialDeposit, initialOnMarket0 + initialOnMarket1);

        vault.deposit(initialDeposit, address(this));

        setSupplyQueueAllMarkets();

        vm.prank(allocator);
        vault.allocate(address(morphoVaultV1Adapter), hex"", initialDeposit);

        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1Adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1)), 0);

        assertEq(underlyingToken.balanceOf(address(morpho)), initialDeposit);
        assertEq(morpho.expectedSupplyAssets(allMarketParams[0], address(morphoVaultV1)), initialOnMarket0);
        assertEq(morpho.expectedSupplyAssets(allMarketParams[1], address(morphoVaultV1)), initialOnMarket1);
    }

    function testNoBadDebtThroughSubmitMarketRemoval() public {
        assertEq(vault.totalAssets(), initialDeposit);
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), initialDeposit);

        // Create bad debt by removing market1.
        vm.startPrank(mmCurator);
        morphoVaultV1.submitCap(allMarketParams[1], 0);
        morphoVaultV1.submitMarketRemoval(allMarketParams[1]);
        skip(morphoVaultV1.timelock());
        uint256[] memory indexes = new uint256[](4);
        indexes[0] = 0;
        indexes[1] = 2;
        indexes[2] = 3;
        indexes[3] = 4;
        morphoVaultV1.updateWithdrawQueue(indexes);
        vm.stopPrank();

        assertEq(vault.totalAssets(), initialDeposit);

        vault.accrueInterest();

        assertEq(vault._totalAssets(), initialDeposit);
    }

    function testNoBadDebtThroughLiquidate() public {
        assertEq(vault.totalAssets(), initialDeposit);
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), initialDeposit);

        // Create bad debt by liquidating everything on market 1.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        uint256 collateralOfBorrower = 3 * initialOnMarket1;
        morpho.supplyCollateral(allMarketParams[1], collateralOfBorrower, borrower, hex"");
        morpho.borrow(allMarketParams[1], initialOnMarket1, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), initialOnMarket0);

        oracle.setPrice(0);

        Id id = allMarketParams[1].id();
        uint256 borrowerShares = morpho.position(id, borrower).borrowShares;
        vm.prank(liquidator);
        // Make sure that a bad debt of initialOnMarket1 is created.
        vm.expectEmit();
        emit MorphoEventsLib.Liquidate(
            id, liquidator, borrower, 0, 0, collateralOfBorrower, initialOnMarket1, borrowerShares
        );
        morpho.liquidate(allMarketParams[1], borrower, collateralOfBorrower, 0, hex"");

        assertEq(vault.totalAssets(), initialDeposit);

        vault.accrueInterest();

        assertEq(vault._totalAssets(), initialDeposit);
    }
}
