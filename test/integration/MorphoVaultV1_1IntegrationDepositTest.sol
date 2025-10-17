// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1_1IntegrationTest.sol";

contract MorphoVaultV1_1IntegrationDepositTest is MorphoVaultV1_1IntegrationTest {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    function testDepositNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, 0, maxTestAssets);

        vault.deposit(assets, address(this));

        checkAssetsInIdle(assets);
        assertEq(morpho.expectedSupplyAssets(idleParams, address(morphoVaultV1)), 0, "expected assets of morphoVaultV1");
    }

    function testDepositLiquidityAdapterSuccess(uint256 assets) public {
        assets = bound(assets, 0, maxTestAssets);

        setSupplyQueueIdle();
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");

        vault.deposit(assets, address(this));

        checkAssetsInMorphoVaultV1Markets(assets);
        assertEq(
            morpho.expectedSupplyAssets(idleParams, address(morphoVaultV1)), assets, "expected assets of morphoVaultV1"
        );
    }

    function testDepositLiquidityAdapterCanFail(uint256 assets) public {
        assets = bound(assets, 0, maxTestAssets);

        setSupplyQueueAllMarkets();
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");

        if (assets > MORPHO_VAULT_V1_NB_MARKETS * CAP) {
            vm.expectRevert();
            vault.deposit(assets, address(this));
        } else {
            vault.deposit(assets, address(this));
            checkAssetsInMorphoVaultV1Markets(assets);
            uint256 positionOnMorpho;
            for (uint256 i; i < MORPHO_VAULT_V1_NB_MARKETS; i++) {
                positionOnMorpho += morpho.expectedSupplyAssets(allMarketParams[i], address(morphoVaultV1));
            }
            assertEq(positionOnMorpho, assets, "expected assets of morphoVaultV1");
        }
    }

    function checkAssetsInMorphoVaultV1Markets(uint256 assets) internal view {
        assertEq(underlyingToken.balanceOf(address(morpho)), assets, "underlying balance of Morpho");
        assertEq(morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter))), assets);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1)), 0, "underlying balance of morphoVaultV1");
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1Adapter)), 0, "underlying balance of adapter");
        assertEq(underlyingToken.balanceOf(address(vault)), 0, "underlying balance of vault");
    }

    function checkAssetsInIdle(uint256 assets) public view {
        assertEq(underlyingToken.balanceOf(address(morpho)), 0, "underlying balance of Morpho");
        assertEq(morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter))), 0);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1)), 0, "underlying balance of morphoVaultV1");
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1Adapter)), 0, "underlying balance of adapter");
        assertEq(underlyingToken.balanceOf(address(vault)), assets, "underlying balance of vault");
    }
}
