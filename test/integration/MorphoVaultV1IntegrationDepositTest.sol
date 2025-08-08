// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1IntegrationTest.sol";

contract MorphoVaultV1IntegrationDepositTest is MorphoVaultV1IntegrationTest {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    function testDepositNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(assets, address(this));

        checkAssetsInIdle(assets);
        assertEq(morpho.expectedSupplyAssets(idleParams, address(morphoVaultV1)), 0, "expected assets of morphoVaultV1");
    }

    function testDepositLiquidityAdapterSuccess(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        setSupplyQueueIdle();
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");

        vault.deposit(assets, address(this));

        checkAssetsInMorphoVaultV1Markets(assets);
        assertEq(
            morpho.expectedSupplyAssets(idleParams, address(morphoVaultV1)), assets, "expected assets of morphoVaultV1"
        );
    }

    function testDepositRoundingLoss(uint256 donationFactor, uint256 roundedDeposit) public {
        // Setup
        donationFactor = bound(donationFactor, 2, 100);
        roundedDeposit = bound(roundedDeposit, 1, donationFactor / 2);
        setSupplyQueueIdle();
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");
        underlyingToken.approve(address(morpho), type(uint256).max);

        // Donate
        morpho.supply(
            idleParams,
            donationFactor * 10 ** IMetaMorpho(morphoVaultV1).DECIMALS_OFFSET() - 1,
            0,
            address(morphoVaultV1),
            hex""
        );
        assertEq(morphoVaultV1.totalSupply(), 0, "total supply");
        assertEq(
            morphoVaultV1.totalAssets(),
            donationFactor * 10 ** IMetaMorpho(morphoVaultV1).DECIMALS_OFFSET() - 1,
            "total assets"
        );
        assertEq(morphoVaultV1.previewRedeem(1), donationFactor, "share price");

        // Check rounded deposit effect
        uint256 previousAdapterShares = morphoVaultV1.balanceOf(address(morphoVaultV1Adapter));
        uint256 previousVaultTotalAssets = vault.totalAssets();
        uint256 previousAdapterTrackedAllocation = morphoVaultV1Adapter.allocation();

        vault.deposit(roundedDeposit, address(this));

        assertEq(
            morphoVaultV1.balanceOf(address(morphoVaultV1Adapter)), previousAdapterShares, "adapter shares balance"
        );
        assertEq(vault.totalAssets(), previousVaultTotalAssets + roundedDeposit, "vault total assets");
        assertEq(
            morphoVaultV1Adapter.allocation(),
            previousAdapterTrackedAllocation,
            "Morpho Vault v1 Adapter tracked allocation"
        );
    }

    function testWithdrawRoundingLoss(uint256 donationFactor, uint256 roundedWithdraw) public {
        donationFactor = bound(donationFactor, 2, 100);
        roundedWithdraw = bound(roundedWithdraw, 1, donationFactor / 2);
        setSupplyQueueIdle();
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");
        underlyingToken.approve(address(morpho), type(uint256).max);

        // Donate
        morpho.supply(
            idleParams,
            donationFactor * 10 ** IMetaMorpho(morphoVaultV1).DECIMALS_OFFSET() - 1,
            0,
            address(morphoVaultV1),
            hex""
        );
        assertEq(morphoVaultV1.totalSupply(), 0, "total supply");
        assertEq(
            morphoVaultV1.totalAssets(),
            donationFactor * 10 ** IMetaMorpho(morphoVaultV1).DECIMALS_OFFSET() - 1,
            "total assets"
        );
        assertEq(morphoVaultV1.previewRedeem(1), donationFactor, "share price");

        // Initial deposit
        // We mint exactly one share otherwise the loss is not exactly the donation factor because you are still in the
        // vault so you profit from the share that has been burned for less than the share price on your other shares,
        // making testing difficult.
        vault.deposit(donationFactor, address(this));
        assertEq(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter)), 1, "shares");

        // Check rounded withdraw effect
        uint256 previousAdapterShares = morphoVaultV1.balanceOf(address(morphoVaultV1Adapter));
        uint256 previousVaultTotalAssets = vault.totalAssets();
        uint256 previousAdapterTrackedAllocation = morphoVaultV1Adapter.allocation();

        vault.withdraw(roundedWithdraw, address(this), address(this));

        assertEq(
            morphoVaultV1.balanceOf(address(morphoVaultV1Adapter)), previousAdapterShares - 1, "adapter shares balance"
        );
        assertEq(vault.totalAssets(), previousVaultTotalAssets - roundedWithdraw, "total assets");
        assertEq(morphoVaultV1Adapter.allocation(), previousAdapterTrackedAllocation - donationFactor, "allocation");
    }

    function testDepositLiquidityAdapterCanFail(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

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
