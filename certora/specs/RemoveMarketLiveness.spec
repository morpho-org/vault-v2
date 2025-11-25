// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoHarness as Morpho;
using Utils as Utils;

methods {
    function _.extSloads(bytes32[]) external => NONDET DELETE;
    function _.multicall(bytes[] data) external => HAVOC_ALL DELETE;
    function _.supplyShares(address, Morpho.Id id, address user) internal => summarySupplyShares(id, user) expect uint256;

    function Morpho.supplyShares(Morpho.Id, address) external returns (uint256) envfree;
    function Morpho.market(Morpho.Id) external returns (uint128, uint128, uint128, uint128, uint128, uint128) envfree;
    function Morpho.lastUpdate(Morpho.Id) external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketIdsLength() external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketIds(uint256) external returns (bytes32) envfree;
    function Utils.decodeMarketParams(bytes data) external returns (Morpho.MarketParams memory) envfree;
    function Utils.id(Morpho.MarketParams) external returns (Morpho.Id) envfree;

    // To fix linking issues.
    function _.deallocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function _.market(Morpho.Id) external => DISPATCHER(true);

    // Assume that the IRM doesn't revert.
    function _.expectedMarketBalances(address, Morpho.Id id, address) internal => summaryExpectedMarketBalances(id) expect (uint256, uint256, uint256, uint256);
}

function summarySupplyShares(Morpho.Id id, address user) returns uint256 {
    return Morpho.supplyShares(id, user);
}

function summaryExpectedMarketBalances(Morpho.Id id) returns (uint256, uint256, uint256, uint256) {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
    (totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares, lastUpdate, fee) = Morpho.market(id);
    return (totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares);
}

// Check that it's possible to put the expected supply assets to zero, assuming that the IRM doesn't revert.
// Together with deallocatingWithZeroExpectedSupplyAssetsRemovesMarket, this proves that it's possible to remove a market.
rule canPutExpectedSupplyAssetsToZero(env e, bytes data) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    Morpho.Id marketId = Utils.id(marketParams);
    require Morpho.lastUpdate(marketId) == e.block.timestamp, "assume that the IRM doesn't revert";

    // Assets to remove to leave the expected supply assets to zero, assuming that the adapter isn't the fee recipient.
    uint256 assets = MorphoMarketV1Adapter.expectedSupplyAssets(e, marketId);

    // Could also check that the deallocate call doesn't revert.
    deallocate(e, MorphoMarketV1Adapter, data, assets);

    assert MorphoMarketV1Adapter.expectedSupplyAssets(e, marketId) == 0;
}

// Check that a deallocation that leaves the expected supply assets to zero removes the market.
rule deallocatingWithZeroExpectedSupplyAssetsRemovesMarket(env e, bytes data, uint256 assets) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    Morpho.Id marketId = Utils.id(marketParams);
    require Morpho.lastUpdate(marketId) == e.block.timestamp, "assume that the IRM doesn't revert";

    uint256 marketIdsLength = MorphoMarketV1Adapter.marketIdsLength();
    require forall uint256 i. forall uint256 j. (i < j && j < marketIdsLength) => MorphoMarketV1Adapter.marketIds[i] != MorphoMarketV1Adapter.marketIds[j], "see distinctMarketIds";

    deallocate(e, MorphoMarketV1Adapter, data, assets);

    require MorphoMarketV1Adapter.expectedSupplyAssets(e, marketId) == 0, "assume that the expected supply assets is left to zero";

    uint256 i;
    require i < MorphoMarketV1Adapter.marketIdsLength();
    assert MorphoMarketV1Adapter.marketIds(i) != marketId;
}
