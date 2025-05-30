// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./MMV1_1IntegrationTest.sol";

contract MMV1_1IntegrationDepositTest is MMV1_1IntegrationTest {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    function testDepositNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(assets, address(this));

        checkAssetsInIdle(assets);
        assertEq(morpho.expectedSupplyAssets(idleParams, address(metaMorpho)), 0, "expected assets of metaMorpho");
    }

    function testDepositLiquidityAdapterSuccess(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        setSupplyQueueIdle();
        vm.prank(allocator);
        vault.setLiquidityAdapter(address(metaMorphoAdapter));

        vault.deposit(assets, address(this));

        checkAssetsInMetaMorphoMarkets(assets);
        assertEq(morpho.expectedSupplyAssets(idleParams, address(metaMorpho)), assets, "expected assets of metaMorpho");
    }

    function testDepositLiquidityAdapterCanFail(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        setSupplyQueueAllMarkets();
        vm.prank(allocator);
        vault.setLiquidityAdapter(address(metaMorphoAdapter));

        vault.deposit(assets, address(this));

        if (assets > MM_NB_MARKETS * CAP) {
            checkAssetsInIdle(assets);
            // No need to check positions on Morpho since Morpho has no balance.
        } else {
            checkAssetsInMetaMorphoMarkets(assets);
            uint256 positionOnMorpho;
            for (uint256 i; i < MM_NB_MARKETS; i++) {
                positionOnMorpho += morpho.expectedSupplyAssets(allMarketParams[i], address(metaMorpho));
            }
            assertEq(positionOnMorpho, assets, "expected assets of metaMorpho");
        }
    }

    function checkAssetsInMetaMorphoMarkets(uint256 assets) internal view {
        assertEq(underlyingToken.balanceOf(address(morpho)), assets, "underlying balance of Morpho");
        assertEq(metaMorpho.previewRedeem(metaMorpho.balanceOf(address(metaMorphoAdapter))), assets);
        assertEq(underlyingToken.balanceOf(address(metaMorpho)), 0, "underlying balance of metaMorpho");
        assertEq(underlyingToken.balanceOf(address(metaMorphoAdapter)), 0, "underlying balance of adapter");
        assertEq(underlyingToken.balanceOf(address(vault)), 0, "underlying balance of vault");
    }

    function checkAssetsInIdle(uint256 assets) public view {
        assertEq(underlyingToken.balanceOf(address(morpho)), 0, "underlying balance of Morpho");
        assertEq(metaMorpho.previewRedeem(metaMorpho.balanceOf(address(metaMorphoAdapter))), 0);
        assertEq(underlyingToken.balanceOf(address(metaMorpho)), 0, "underlying balance of metaMorpho");
        assertEq(underlyingToken.balanceOf(address(metaMorphoAdapter)), 0, "underlying balance of adapter");
        assertEq(underlyingToken.balanceOf(address(vault)), assets, "underlying balance of vault");
    }
}
