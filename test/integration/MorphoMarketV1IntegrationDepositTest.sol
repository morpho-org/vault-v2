// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";

contract MorphoMarketV1IntegrationDepositTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    function testDepositNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(assets, address(this));

        assertEq(underlyingToken.balanceOf(address(vault)), assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), 0);
        assertEq(morpho.expectedSupplyAssets(marketParams2, address(adapter)), 0);
        assertEq(vault.allocation(keccak256(expectedIdData1[0])), 0);
    }

    function testDepositLiquidityAdapterSuccess(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), abi.encode(marketParams1));

        vault.deposit(assets, address(this));

        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), assets);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), assets);
        assertEq(morpho.expectedSupplyAssets(marketParams2, address(adapter)), 0);
        assertEq(vault.allocation(keccak256(expectedIdData1[0])), assets);
    }
}
