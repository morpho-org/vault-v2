// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1IntegrationTest.sol";

contract MorphoVaultV1IntegrationDonationTest is MorphoVaultV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable donor = makeAddr("donor");

    function testSharesDonationResistanceIfNoAllocation(uint256 initialAssets, uint256 donatedAssets, uint256 elapsed)
        public
    {
        initialAssets = bound(initialAssets, 0, MAX_TEST_ASSETS);
        donatedAssets = bound(donatedAssets, 0, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 0, 10 * 365 days);

        setSupplyQueueIdle();

        vault.deposit(initialAssets, address(this));

        assertEq(vault.totalAssets(), initialAssets, "initialAssets");

        deal(address(underlyingToken), donor, donatedAssets);
        vm.startPrank(donor);
        underlyingToken.approve(address(morphoVaultV1), type(uint256).max);
        morphoVaultV1.deposit(donatedAssets, address(morphoVaultV1Adapter));
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(morpho)), donatedAssets, "underlying balance of Morpho");
        assertEq(morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter))), donatedAssets);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1Adapter)), 0, "underlying balance of adapter");
        assertEq(underlyingToken.balanceOf(address(vault)), initialAssets, "underlying balance of vault");
        assertEq(
            morpho.expectedSupplyAssets(idleParams, address(morphoVaultV1)),
            donatedAssets,
            "expected donatedAssets of morphoVaultV1"
        );

        skip(elapsed);
        assertEq(vault.totalAssets(), initialAssets, "not donation resistant");
    }
}
