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
    function Morpho.lastUpdate(Morpho.Id) external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketIdsLength() external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketIds(uint256) external returns (bytes32) envfree;
    function Utils.decodeMarketParams(bytes data) external returns (Morpho.MarketParams memory) envfree;
    function Utils.id(Morpho.MarketParams) external returns (Morpho.Id) envfree;

    function _.deallocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);

    // Todo: remove once it's linked to ERC20Mock.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => ghostBorrowRate expect uint256;
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => ghostBorrowRate expect uint256;

    function _.market(Morpho.Id) external => DISPATCHER(true);
}

persistent ghost uint256 ghostBorrowRate;

function summarySupplyShares(Morpho.Id id, address user) returns uint256 {
    return Morpho.supplyShares(id, user);
}

// Check that it's possible to put the expected supply assets to zero, assuming that the IRM isn't reverting.
// Together with deallocatingWithZeroExpectedSupplyAssetsRemovesMarket, this proves that it's possible to remove a market.
rule canPutExpectedSupplyAssetsToZero(env e, bytes data) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    Morpho.Id marketId = Utils.id(marketParams);
    // require Morpho.feeRecipient != MorphoMarketV1Adapter, "sane assumption to simplify the amount of asset to remove";
    require Morpho.lastUpdate(marketId) == e.block.timestamp, "assume that the IRM isn't reverting";
    uint256 assets = MorphoMarketV1Adapter.expectedSupplyAssets(e, marketId);

    uint256 marketIdsLength = MorphoMarketV1Adapter.marketIdsLength();
    require forall uint256 i. forall uint256 j. (i < j && j < marketIdsLength) => MorphoMarketV1Adapter.marketIds[i] != MorphoMarketV1Adapter.marketIds[j], "see distinctMarketIds";

    // Could also check that the deallocate call doesn't revert.
    deallocate(e, MorphoMarketV1Adapter, data, assets);

    assert MorphoMarketV1Adapter.expectedSupplyAssets(e, marketId) == 0;
}

// Check that a deallocation that leaves the expected supply assets to zero removes the market.
rule deallocatingWithZeroExpectedSupplyAssetsRemovesMarket(env e, bytes data, uint256 assets) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    bytes32 marketId = Utils.id(marketParams);

    deallocate(e, MorphoMarketV1Adapter, data, assets);

    require MorphoMarketV1Adapter.expectedSupplyAssets(e, marketId) == 0;

    uint256 i;
    require i < MorphoMarketV1Adapter.marketIdsLength();
    assert MorphoMarketV1Adapter.marketIds(i) != marketId;
}
