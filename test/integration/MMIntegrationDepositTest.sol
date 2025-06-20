// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MMIntegrationTest.sol";

contract MMIntegrationDepositTest is MMIntegrationTest {
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
        vault.setLiquidityMarket(address(metaMorphoAdapter), hex"");

        vault.deposit(assets, address(this));

        checkAssetsInMetaMorphoMarkets(assets);
        assertEq(morpho.expectedSupplyAssets(idleParams, address(metaMorpho)), assets, "expected assets of metaMorpho");
    }

    function testDepositRoundingLoss(uint256 donation, uint256 roundedDeposit) public {
        // Setup
        donation = bound(donation, 1, MAX_TEST_ASSETS);
        roundedDeposit = bound(roundedDeposit, 1, donation);
        setSupplyQueueIdle();
        vm.prank(allocator);
        vault.setLiquidityMarket(address(metaMorphoAdapter), hex"");
        underlyingToken.approve(address(morpho), type(uint256).max);

        // Donate
        morpho.supply(idleParams, donation, 0, address(metaMorpho), hex"");

        // Check rounded deposit effect
        uint256 previousAdapterShares = metaMorpho.balanceOf(address(metaMorphoAdapter));
        uint256 previousVaultTotalAssets = vault.totalAssets();
        uint256 previousAdapterTrackedAllocation = metaMorphoAdapter.allocation();

        vault.deposit(roundedDeposit, address(this));

        assertEq(metaMorpho.balanceOf(address(metaMorphoAdapter)), previousAdapterShares, "adapter shares balance");
        assertEq(vault.totalAssets(), previousVaultTotalAssets + roundedDeposit, "vault total assets");
        assertEq(
            metaMorphoAdapter.allocation(),
            previousAdapterTrackedAllocation + roundedDeposit,
            "MM Adapter tracked allocation"
        );

        // Check rounding is realizable
        vault.realizeLoss(address(metaMorphoAdapter), "");

        assertEq(vault.totalAssets(), previousVaultTotalAssets, "vault total assets, after");
        assertEq(
            metaMorphoAdapter.allocation(),
            previousAdapterTrackedAllocation,
            "MM Adapter tracked allocation, after"
        );
    }

    function testWithdrawRoundingLoss(uint256 initialDeposit, uint256 donationFactor, uint256 roundedWithdraw) public {
        // Setup
        initialDeposit = 1e18;
        donationFactor = bound(donationFactor, 2, 100);
        roundedWithdraw = bound(roundedWithdraw, 1, donationFactor / 2);
        setSupplyQueueIdle();
        vm.prank(allocator);
        vault.setLiquidityMarket(address(metaMorphoAdapter), hex"");
        underlyingToken.approve(address(morpho), type(uint256).max);

        // Donate
        morpho.supply(idleParams, donationFactor, 0, address(metaMorpho), hex"");

        // Initial deposit
        vault.deposit(initialDeposit * donationFactor, address(this));

        // Check rounded withdraw effect
        uint256 previousAdapterShares = metaMorpho.balanceOf(address(metaMorphoAdapter));
        uint256 previousVaultTotalAssets = vault.totalAssets();
        uint256 previousAdapterTrackedAllocation = metaMorphoAdapter.allocation();

        vault.withdraw(roundedWithdraw, address(this), address(this));

        assertEq(metaMorpho.balanceOf(address(metaMorphoAdapter)), previousAdapterShares - 1, "adapter shares balance");
        assertEq(vault.totalAssets(), previousVaultTotalAssets - roundedWithdraw, "vault total assets");
        assertEq(
            metaMorphoAdapter.allocation(),
            previousAdapterTrackedAllocation - roundedWithdraw,
            "MM Adapter tracked allocation"
        );

        // Check rounding is realizable
        vault.realizeLoss(address(metaMorphoAdapter), "");

        assertLt(vault.totalAssets(), previousVaultTotalAssets - roundedWithdraw, "vault total assets, after");
        assertLt(
            metaMorphoAdapter.allocation(),
            previousAdapterTrackedAllocation - roundedWithdraw,
            "MM Adapter tracked allocation, after"
        );
    }

    function testDepositLiquidityAdapterCanFail(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        setSupplyQueueAllMarkets();
        vm.prank(allocator);
        vault.setLiquidityMarket(address(metaMorphoAdapter), hex"");

        if (assets > MM_NB_MARKETS * CAP) {
            vm.expectRevert();
            vault.deposit(assets, address(this));
        } else {
            vault.deposit(assets, address(this));
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
