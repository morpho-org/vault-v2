// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoHarness as Morpho;
using Utils as Utils;

methods {
    function _.extSloads(bytes32[]) external => NONDET DELETE;
    function _.multicall(bytes[] data) external => HAVOC_ALL DELETE;

    function Morpho.market(Morpho.Id) external returns (uint128, uint128, uint128, uint128, uint128, uint128) envfree;
    function Morpho.lastUpdate(Morpho.Id) external returns (uint256) envfree;
    function Morpho.supplyShares(Morpho.Id, address) external returns (uint256) envfree;
    function Morpho.totalSupplyShares(Morpho.Id) external returns (uint256) envfree;
    function Morpho.totalSupplyAssets(Morpho.Id) external returns (uint256) envfree;
    function Morpho.totalBorrowAssets(Morpho.Id) external returns (uint256) envfree;
    function MorphoMarketV1Adapter.asset() external returns (address) envfree;
    function MorphoMarketV1Adapter.adaptiveCurveIrm() external returns (address) envfree;
    function MorphoMarketV1Adapter.marketIdsLength() external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketIds(uint256) external returns (bytes32) envfree;
    function MorphoMarketV1Adapter.allocation(Morpho.MarketParams) external returns (uint256) envfree;
    function MorphoMarketV1Adapter.supplyShares(bytes32) external returns (uint256) envfree;
    function Utils.decodeMarketParams(bytes data) external returns (Morpho.MarketParams memory) envfree;
    function Utils.id(Morpho.MarketParams) external returns (Morpho.Id) envfree;
    function Utils.wrapId(bytes32) external returns (Morpho.Id) envfree;
    function Utils.unwrapId(Morpho.Id) external returns (bytes32) envfree;
    function isAdapter(address) external returns bool envfree;
    function isAllocator(address) external returns bool envfree;
    function isSentinel(address) external returns bool envfree;

    // To fix linking issues.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // Assume that the allocation of the market from which to deallocate is positive.
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with (env e) => summaryDeallocate(e, data, assets, selector, sender) expect (bytes32[], int256);

    // Assume that the IRM doesn't revert.
    function _.expectedMarketBalances(address, bytes32 id, address) internal => summaryExpectedMarketBalances(id) expect (uint256, uint256, uint256, uint256);
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

function summaryExpectedMarketBalances(bytes32 id) returns (uint256, uint256, uint256, uint256) {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
    (totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares, lastUpdate, fee) = Morpho.market(Utils.wrapId(id));
    return (totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares);
}

function summaryDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;
    ids, change = MorphoMarketV1Adapter.deallocate(e, data, assets, selector, sender);
    require ids.length == 3;
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "assume that the allocation is positive";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= max_int256(), "see allocationIsInt256";
    require currentContract.caps[ids[0]].allocation >= currentContract.caps[ids[2]].allocation, "adapter id allocation is a sum of market id allocation";
    require currentContract.caps[ids[1]].allocation >= currentContract.caps[ids[2]].allocation, "collateral token id allocation is a sum of market id allocation";
    return (ids, change);
}

// Check that it's possible deallocate expected supply assets, assuming that the IRM doesn't revert and that there is enough liquidity on the market.
rule canDeallocateExpectedSupplyAssets(env e, bytes data) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    Morpho.Id marketId = Utils.id(marketParams);
    bytes32 id = Utils.unwrapId(marketId);
    require Morpho.lastUpdate(marketId) == e.block.timestamp, "assume that the IRM doesn't revert";

    uint256 assets = MorphoMarketV1Adapter.expectedSupplyAssets(e, marketId);

    require Morpho.totalSupplyAssets(marketId) - assets >= Morpho.totalBorrowAssets(marketId), "assume enough liquidity";

    require MorphoMarketV1Adapter.supplyShares(id) <= Morpho.supplyShares(marketId, MorphoMarketV1Adapter), "internal accounting of shares is less than actual held shares";
    require Morpho.supplyShares(marketId, MorphoMarketV1Adapter) <= Morpho.totalSupplyShares(marketId), "total supply shares is the sum of the market supply shares";
    require Morpho.supplyShares(marketId, MorphoMarketV1Adapter) < 2^128, "shares fit on 128 bits on Morpho";
    require assets < 10^32, "safe because market v1 specifies that loan tokens should have less than 1e32 total supply";
    require Morpho.lastUpdate(marketId) != 0, "assume the market is created";
    require isAdapter(MorphoMarketV1Adapter), "assume the adapter is enabled";
    require isSentinel(e.msg.sender) || isAllocator(e.msg.sender), "setup the call";
    require e.msg.value == 0, "setup the call";
    require marketParams.loanToken == MorphoMarketV1Adapter.asset(), "setup the call";
    require marketParams.irm == MorphoMarketV1Adapter.adaptiveCurveIrm(), "setup the call";

    deallocate@withrevert(e, MorphoMarketV1Adapter, data, assets);

    assert !lastReverted;
}

function canPutExpectedSupplyAssetsToZero(env e, bytes data) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    Morpho.Id marketId = Utils.id(marketParams);
    require Morpho.lastUpdate(marketId) == e.block.timestamp, "assume that the IRM doesn't revert";

    uint256 assets = MorphoMarketV1Adapter.expectedSupplyAssets(e, marketId);

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

    require MorphoMarketV1Adapter.expectedSupplyAssets(e, marketId) == 0, "assume that the expected supply assets is put to zero";

    uint256 i;
    require i < MorphoMarketV1Adapter.marketIdsLength(), "only check valid indices";
    assert MorphoMarketV1Adapter.marketIds(i) != marketId;
}
