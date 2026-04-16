// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";

contract MorphoMarketV1IntegrationBurnSharesTest is MorphoMarketV1IntegrationTest {
    using MarketParamsLib for MarketParams;

    function testBurnShares(uint256 assets) public {
        // Initial deposit
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), abi.encode(marketParams1));
        vault.deposit(assets, address(this));

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), abi.encode(marketParams2));
        vault.deposit(assets, address(this));

        assertEq(vault.allocation(expectedIds1[0]), assets * 2, "market1 0 before");
        assertEq(vault.allocation(expectedIds1[1]), assets * 2, "market1 1 before");
        assertEq(vault.allocation(expectedIds1[2]), assets, "market1 2 before");

        assertEq(vault.allocation(expectedIds2[2]), assets, "market2 2 before");

        // Burn shares at adapter level
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMorphoMarketV1AdapterV2.burnShares, (Id.unwrap(marketParams1.id()))));
        adapter.burnShares(Id.unwrap(marketParams1.id()));

        // Ping adapter from vault
        vault.forceDeallocate(address(adapter), abi.encode(marketParams1), 0, address(this));

        assertEq(vault.allocation(expectedIds1[0]), assets, "market1 0 after");
        assertEq(vault.allocation(expectedIds1[1]), assets, "market1 1 after");
        assertEq(vault.allocation(expectedIds1[2]), 0, "market1 2 after");

        assertEq(vault.allocation(expectedIds2[2]), assets, "market2 2 after");
    }
}
