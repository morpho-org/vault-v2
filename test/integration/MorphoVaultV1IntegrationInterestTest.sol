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
        assets = bound(assets, 1, maxTestAssets);
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

        assertEq(
            morphoVaultV1.totalAssets(),
            morpho.expectedSupplyAssets(allMarketParams[0], address(morphoVaultV1)),
            "vault V1 totalAssets"
        );
        // slightly off from the market's expectedSupplyAssets because of the vaultV1 virtual shares.
        uint256 expectedSupplyAssets =
            morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter)));
        uint256 maxTotalAssets = assets + (assets * elapsed).mulDivDown(MAX_MAX_RATE, WAD);
        uint256 expectedTotalAssets = MathLib.min(expectedSupplyAssets, maxTotalAssets);
        assertEq(vault.totalAssets(), expectedTotalAssets, "vault totalAssets");
    }
}
