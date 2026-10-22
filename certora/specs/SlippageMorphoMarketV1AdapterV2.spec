// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function supplyShares(bytes32) external returns (uint256) envfree;
    function MorphoMarketV1.totalSupplyAssets(MorphoHarness.Id) external returns (uint256) envfree;
    function MorphoMarketV1.totalSupplyShares(MorphoHarness.Id) external returns (uint256) envfree;
    function Utils.decodeMarketParams(bytes) external returns (MorphoHarness.MarketParams) envfree;
    function Utils.id(MorphoHarness.MarketParams) external returns (MorphoHarness.Id) envfree;
    function Utils.unwrapId(MorphoHarness.Id) external returns (bytes32) envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => constantBorrowRate expect(uint256);
    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect(uint256);

    function _.onMorphoSupply(uint256, bytes) external => NONDET;
}

persistent ghost uint256 constantBorrowRate;

// Check that each allocation gets the adapter shares for at most one asset each.
rule allocateGetsSharesForAtMostOneAssetEach(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
    bytes32 marketId = Utils.unwrapId(Utils.id(Utils.decodeMarketParams(data)));
    uint256 sharesBefore = supplyShares(marketId);

    allocate(e, data, assets, selector, sender);

    assert supplyShares(marketId) - sharesBefore >= assets;
}

// Check that each deallocation burns less than one share in excess of the withdrawn assets, at the share price of the market.
// Together with allocateGetsSharesForAtMostOneAssetEach, this means that deallocating loses at most one asset.
rule deallocateLosesLessThanOneShare(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
    MorphoHarness.Id id = Utils.id(Utils.decodeMarketParams(data));
    bytes32 marketId = Utils.unwrapId(id);
    uint256 sharesBefore = supplyShares(marketId);

    deallocate(e, data, assets, selector, sender);

    mathint burnedShares = sharesBefore - supplyShares(marketId);

    // Market totals right before the withdrawal, after interest accrual.
    mathint totalAssets = MorphoMarketV1.totalSupplyAssets(id) + assets;
    mathint totalShares = MorphoMarketV1.totalSupplyShares(id) + burnedShares;

    assert (burnedShares - 1) * (totalAssets + 1) < assets * (totalShares + 10 ^ 6);
}
