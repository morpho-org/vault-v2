// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";

contract MorphoMarketV1IntegrationForceRemoveTest is MorphoMarketV1IntegrationTest {
    MarketParams internal marketParams2;
    MorphoMarketV1Adapter internal adapter2;
    bytes internal adapter2IdData;

    function setUp() public virtual override {
        super.setUp();

        marketParams2 = MarketParams({
            loanToken: address(underlyingToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            oracle: address(oracle),
            lltv: 0.9 ether
        });

        morpho.createMarket(marketParams2);

        adapter2 =
            MorphoMarketV1Adapter(factory.createMorphoMarketV1Adapter(address(vault), address(morpho), marketParams2));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter2))));
        vault.addAdapter(address(adapter2));

        adapter2IdData = abi.encode("this", address(adapter2));

        increaseAbsoluteCap(adapter2IdData, type(uint128).max);
        increaseRelativeCap(adapter2IdData, WAD);
    }

    function testForceRemove(uint256 assets) public {
        // Initial deposit
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");
        vault.deposit(assets, address(this));

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter2), hex"");
        vault.deposit(assets, address(this));

        assertEq(vault.allocation(expectedIds[0]), assets * 2, "market v1 before");
        assertEq(vault.allocation(expectedIds[1]), assets, "adapter before");
        assertEq(vault.allocation(expectedIds[2]), assets * 2, "collateral before");

        assertEq(vault.allocation(keccak256(adapter2IdData)), assets, "adapter2 before");

        // Force remove at adapter level
        vm.prank(curator);
        adapter.submitForceRemove();
        adapter.forceRemove();

        // Ping adapter from vault
        vault.forceDeallocate(address(adapter), hex"", 0, address(this));

        assertEq(vault.allocation(expectedIds[0]), assets, "market v1 after");
        assertEq(vault.allocation(expectedIds[1]), 0, "adapter after");
        assertEq(vault.allocation(expectedIds[2]), assets, "collateral after");

        assertEq(vault.allocation(keccak256(adapter2IdData)), assets, "adapter2 after");
    }
}
