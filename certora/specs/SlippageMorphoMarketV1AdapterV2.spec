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
    function MorphoMarketV1.lastUpdate(MorphoHarness.Id) external returns (uint256) envfree;
    function Utils.unwrapId(MorphoHarness.Id) external returns (bytes32) envfree;

    function allocation(MorphoHarness.MarketParams memory) internal returns (uint256) => NONDET;
    function expectedSupplyAssets(bytes32) internal returns (uint256) => NONDET;
    function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => NONDET;
    function MathLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // Sound because the rules only look at the supply shares of the adapter and the market totals.
    function updateList(bytes32, uint256, uint256) internal => NONDET;
    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;

    // Sound because the intermediary state is a valid state, except for token balances, which this spec doesn't look at.
    function _.onMorphoSupply(uint256, bytes) external => NONDET;

    // Sound because this spec doesn't look at token balances.
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
}

persistent ghost uint256 constantBorrowRate;

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    bool shouldRevert;
    if (shouldRevert) {
        revert();
    }

    // Both requires are proven in MathLibSummaries.spec.
    require result * d >= x * y, "result is at least x * y / d";
    require (result - 1) * d < x * y, "result is less than x * y / d plus one";
    return result;
}

// Check that each allocation gets the adapter shares for at most one asset each.
rule allocateGetsSharesForAtMostOneAssetEach(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
    bytes32 marketId = Utils.unwrapId(Utils.id(Utils.decodeMarketParams(data)));
    uint256 sharesBefore = supplyShares(marketId);

    allocate(e, data, assets, selector, sender);

    assert supplyShares(marketId) - sharesBefore >= assets;
}

// Check that each deallocation burns less than one share in excess of the withdrawn assets, at the share price of the market.
// Together with allocateGetsSharesForAtMostOneAssetEach, this means that deallocating loses at most one asset: the adapter loses at most one more share than the fair price, but each share was acquired for less than one asset.
rule deallocateLosesLessThanOneShare(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
    MorphoHarness.Id id = Utils.id(Utils.decodeMarketParams(data));
    bytes32 marketId = Utils.unwrapId(id);
    uint256 sharesBefore = supplyShares(marketId);

    // Safe because the market totals are taken after interest accrual, and accruing interest twice in the same block is a no-op.
    require MorphoMarketV1.lastUpdate(id) == e.block.timestamp, "assume interest is already accrued";

    mathint totalAssets = MorphoMarketV1.totalSupplyAssets(id);
    mathint totalShares = MorphoMarketV1.totalSupplyShares(id);

    deallocate(e, data, assets, selector, sender);

    mathint burnedShares = sharesBefore - supplyShares(marketId);

    assert (burnedShares - 1) * (totalAssets + 1) < assets * (totalShares + 10 ^ 6);
}
