// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";

contract MorphoMarketV1IntegrationInterestTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;
    using MathLib for uint256;

    /// forge-config: default.isolate = true
    function testAccrueInterest(uint256 assets, uint256 elapsed) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 0, 10 * 365 days);

        // setup.
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), abi.encode(marketParams1));
        vault.deposit(assets, address(this));

        // accrue some interest on the underlying market.
        deal(address(collateralToken), address(this), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams1, assets * 2, address(this), hex"");
        morpho.borrow(marketParams1, assets, 0, address(this), address(this));
        skip(elapsed);

        uint256 expectedSupplyAssets = morpho.expectedSupplyAssets(marketParams1, address(adapter));
        uint256 maxTotalAssets = assets + (assets * elapsed).mulDivDown(MAX_MAX_RATE, WAD);
        assertEq(vault.totalAssets(), MathLib.min(expectedSupplyAssets, maxTotalAssets), "vault totalAssets");
    }
}
