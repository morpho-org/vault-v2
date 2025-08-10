// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1IntegrationTest.sol";

contract MorphoVaultV1IntegrationInterestTest is MorphoVaultV1IntegrationTest {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;
    using MathLib for uint256;

    /// forge-config: default.isolate = true
    function testAccrueInterest(uint256 assets, uint256 elapsed) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 0, 10 * 365 days);

        // setup.
        setSupplyQueueAllMarkets();
        setMorphoVaultV1Cap(allMarketParams[0], type(uint184).max);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");
        vault.deposit(assets, address(this));

        // accrue some interest on the underlying market.
        deal(address(collateralToken), address(this), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(allMarketParams[0], assets * 2, address(this), hex"");
        morpho.borrow(allMarketParams[0], assets, 0, address(this), address(this));
        skip(elapsed);

        uint256 expectedSupplyAssets = morpho.expectedSupplyAssets(allMarketParams[0], address(morphoVaultV1));
        assertEq(morphoVaultV1.totalAssets(), expectedSupplyAssets, "vault v1 totalAssets");
        uint256 maxTotalAssets = assets + (assets * elapsed).mulDivDown(MAX_MAX_RATE, WAD);
        // approx due to the virtual share in the vault v1.
        assertApproxEqRel(
            vault.totalAssets(), MathLib.min(expectedSupplyAssets, maxTotalAssets), WAD / assets, "vault totalAssets"
        );
    }
}
