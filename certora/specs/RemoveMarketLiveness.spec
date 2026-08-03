// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using BlueAdapterV3 as BlueAdapterV3;
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
    function BlueAdapterV3.asset() external returns (address) envfree;
    function BlueAdapterV3.marketIdsLength() external returns (uint256) envfree;
    function BlueAdapterV3.marketIds(uint256) external returns (bytes32) envfree;
    function BlueAdapterV3.allocation(Morpho.MarketParams) external returns (uint256) envfree;
    function BlueAdapterV3.supplyShares(bytes32) external returns (uint256) envfree;
    function Utils.decodeMarketParams(bytes data) external returns (Morpho.MarketParams memory) envfree;
    function Utils.id(Morpho.MarketParams) external returns (Morpho.Id) envfree;
    function Utils.wrapId(bytes32) external returns (Morpho.Id) envfree;
    function Utils.unwrapId(Morpho.Id) external returns (bytes32) envfree;

    // To simplify linking that should be done in the vault, as well as in Morpho.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryDeallocate(e, data, assets, selector, sender) expect(bytes32[], int256);

    // Assume that the IRM doesn't revert.
    function _.expectedMarketBalances(address, Morpho.MarketParams marketParams) internal => summaryExpectedMarketBalances(marketParams) expect(uint256, uint256, uint256, uint256);
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

function summaryExpectedMarketBalances(Morpho.MarketParams marketParams) returns (uint256, uint256, uint256, uint256) {
    Morpho.Id id = Utils.id(marketParams);
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
    totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares, lastUpdate, fee = Morpho.market(id);
    return (totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares);
}

function summaryDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;
    ids, change = BlueAdapterV3.deallocate(e, data, assets, selector, sender);
    require ids.length == 3, "see IdsBlueAdapterV3";

    // See distinctBlueAdapterV3Ids rule.
    require ids[0] != ids[1], "ack";
    require ids[0] != ids[2], "ack";
    require ids[1] != ids[2], "ack";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "assume that the allocation is positive";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation < 2 ^ 20 * 2 ^ 128, "Morpho Blue fits total supply assets on 128 bits, and assume at most 2^20 markets";
    require change < 2 ^ 128, "Morpho Blue fits total supply assets on 128 bits";
    require currentContract.caps[ids[0]].allocation >= currentContract.caps[ids[2]].allocation, "see groupAllocationGteLeafAllocation in AllocationsHierarchy.spec";
    require currentContract.caps[ids[1]].allocation >= currentContract.caps[ids[2]].allocation, "see groupAllocationGteLeafAllocation in AllocationsHierarchy.spec";
    return (ids, change);
}

// Check that it's possible deallocate expected supply assets, assuming that the IRM doesn't revert and that there is enough liquidity on the market.
rule canDeallocateExpectedSupplyAssets(env e, bytes data) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    Morpho.Id marketId = Utils.id(marketParams);
    bytes32 id = Utils.unwrapId(marketId);
    require Morpho.lastUpdate(marketId) == e.block.timestamp, "assume that the IRM doesn't revert";

    uint256 assets = BlueAdapterV3.expectedSupplyAssets(e, marketId);

    require Morpho.totalSupplyAssets(marketId) - assets >= Morpho.totalBorrowAssets(marketId), "assume enough liquidity";

    require BlueAdapterV3.allocation(marketParams) <= max_int256(), "see allocationIsInt256";
    require BlueAdapterV3.supplyShares(id) <= Morpho.supplyShares(marketId, BlueAdapterV3), "internal accounting of shares is less than actual held shares";
    require Morpho.supplyShares(marketId, BlueAdapterV3) <= Morpho.totalSupplyShares(marketId), "total supply shares is the sum of the market supply shares";
    require Morpho.supplyShares(marketId, BlueAdapterV3) < 2 ^ 128, "shares fit on 128 bits on Morpho";
    require assets < 10 ^ 32, "safe because Morpho Blue specifies that loan tokens should have less than 1e32 total supply";
    require Morpho.lastUpdate(marketId) != 0, "assume the market is created";
    require isAdapter(BlueAdapterV3), "assume the adapter is enabled";
    require isSentinel(e.msg.sender) || isAllocator(e.msg.sender), "setup the call";
    require e.msg.value == 0, "setup the call";
    require marketParams.loanToken == BlueAdapterV3.asset(), "setup the call";

    deallocate@withrevert(e, BlueAdapterV3, data, assets);

    assert !lastReverted;
}

// Check that deallocating expected supply assets puts the expected supply assets to zero.
rule canPutExpectedSupplyAssetsToZero(env e, bytes data) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    Morpho.Id marketId = Utils.id(marketParams);
    require Morpho.lastUpdate(marketId) == e.block.timestamp, "assume that the IRM doesn't revert";

    uint256 assets = BlueAdapterV3.expectedSupplyAssets(e, marketId);

    deallocate(e, BlueAdapterV3, data, assets);

    assert BlueAdapterV3.expectedSupplyAssets(e, marketId) == 0;
}

// Check that a deallocation that leaves the expected supply assets to zero removes the market.
rule deallocatingWithZeroExpectedSupplyAssetsRemovesMarket(env e, bytes data, uint256 assets) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    Morpho.Id marketId = Utils.id(marketParams);
    require Morpho.lastUpdate(marketId) == e.block.timestamp, "assume that the IRM doesn't revert";

    uint256 marketIdsLength = BlueAdapterV3.marketIdsLength();
    require forall uint256 i. forall uint256 j. (i < j && j < marketIdsLength) => BlueAdapterV3.marketIds[i] != BlueAdapterV3.marketIds[j], "see distinctMarketIds";

    deallocate(e, BlueAdapterV3, data, assets);

    require BlueAdapterV3.expectedSupplyAssets(e, marketId) == 0, "assume that the expected supply assets is put to zero";

    uint256 i;
    assert BlueAdapterV3.marketIds(i) != marketId;
}
