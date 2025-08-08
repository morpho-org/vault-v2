// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function allocation(bytes32) external returns uint256 envfree;
    function MorphoMarketV1.totalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function MorphoMarketV1.totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function MorphoMarketV1.position_(MorphoHarness.Id, address) external returns MorphoHarness.Position envfree;
    function MorphoMarketV1Adapter.ids(MorphoHarness.MarketParams) external returns bytes32[] envfree;
    function MorphoMarketV1Adapter.allocation(MorphoHarness.MarketParams) external returns uint256 envfree;
    function Utils.morphoMarketV1MarketParams(bytes) external returns (MorphoHarness.MarketParams, MorphoHarness.Id) envfree;

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect uint256;
    function _.borrowRateView(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect uint256;

    function _.allocate(bytes data, uint256 assets, bytes4 bs, address a) external with (env e)
        => morphoMarketV1AdapterWrapperSummary(e, true, data, assets, bs, a) expect (bytes32[], int256);
    function _.deallocate(bytes data, uint256 assets, bytes4 bs, address a) external with (env e)
        => morphoMarketV1AdapterWrapperSummary(e, false, data, assets, bs, a) expect (bytes32[], int256);

    function _.market(MorphoHarness.Id) external => DISPATCHER(true);
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
}

persistent ghost uint256 constantBorrowRate;

persistent ghost int256 ghostChange;

// Wrapper to record interest value returned by the adapter and ensure returned ids are unique.
function morphoMarketV1AdapterWrapperSummary(env e, bool isAllocateCall, bytes data, uint256 assets, bytes4 bs, address a) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    if (isAllocateCall) {
        (ids, change) = MorphoMarketV1Adapter.allocate(e, data, assets, bs, a);
    } else {
        (ids, change) = MorphoMarketV1Adapter.deallocate(e, data, assets, bs, a);
    }

    require (forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "assume that all returned ids are unique");
    ghostChange = change;

    return (ids, change);
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

strong invariant allocationIsInt256(bytes32 id)
    allocation(id) <= max_int256();

rule allocateMorphoMarketV1Adapter(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    MorphoHarness.MarketParams marketParams;
    (marketParams, _) = Utils.morphoMarketV1MarketParams(data);

    // Ensure the VaultV2 and Morpho contracts are properly linked to the adapter in the conf file.
    assert MorphoMarketV1Adapter.parentVault == currentContract;
    assert MorphoMarketV1Adapter.morpho == MorphoMarketV1;

    bytes32[] adapterIds = MorphoMarketV1Adapter.ids(marketParams);

    uint i;
    require (i < adapterIds.length, "require i to be a valid index");
    bytes32 id;

    uint256 allocationBefore = allocation(id);

    requireInvariant allocationIsInt256(adapterIds[i]);
    int256 idIAllocationBefore = assert_int256(allocation(adapterIds[i]));

    allocate(e, MorphoMarketV1Adapter, data, assets);

    assert adapterIds = MorphoMarketV1Adapter.ids(marketParams);
    assert allocation(adapterIds[i]) == idIAllocationBefore + ghostChange;
    assert !(exists uint j . j < adapterIds.length && id == adapterIds[j]) => allocation(id) == allocationBefore;
}

rule allocationAfterAllocate(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    // Ensure the VaultV2 and Morpho contracts are properly linked to the adapter in the conf file.
    assert MorphoMarketV1Adapter.parentVault == currentContract;
    assert MorphoMarketV1Adapter.morpho == MorphoMarketV1;

    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id marketId;
    (marketParams, marketId) = Utils.morphoMarketV1MarketParams(data);

    allocate(e, MorphoMarketV1Adapter, data, assets);

    uint256 allocation = MorphoMarketV1Adapter.allocation(marketParams);
    uint256 supplyShares = MorphoMarketV1.position_(marketId, MorphoMarketV1Adapter).supplyShares;
    uint256 expected = Utils.expectedSupplyAssets(e, MorphoMarketV1, marketParams, supplyShares);

    assert allocation >= expected;
}

rule deallocateMorphoMarketV1Adapter(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    MorphoHarness.MarketParams marketParams;
    (marketParams, _) = Utils.morphoMarketV1MarketParams(data);

    // Ensure the VaultV2 and Morpho contracts are properly linked to the adapter in the conf file.
    assert MorphoMarketV1Adapter.parentVault == currentContract;
    assert MorphoMarketV1Adapter.morpho == MorphoMarketV1;

    bytes32[] adapterIds = MorphoMarketV1Adapter.ids(marketParams);

    uint i;
    require (i < adapterIds.length, "require i to be a valid index");
    bytes32 id;
    uint256 allocationBefore = allocation(id);

    requireInvariant allocationIsInt256(adapterIds[i]);
    int256 idIAllocationBefore = assert_int256(allocation(adapterIds[i]));

    deallocate(e, MorphoMarketV1Adapter, data, assets);

    assert adapterIds = MorphoMarketV1Adapter.ids(marketParams);
    assert allocation(adapterIds[i]) == idIAllocationBefore + ghostChange;
    assert !(exists uint j . j < adapterIds.length && id == adapterIds[j]) => allocation(id) == allocationBefore;
}

rule allocationAfterDeallocate(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    // Ensure the VaultV2 and Morpho contracts are properly linked to the adapter in the conf file.
    assert MorphoMarketV1Adapter.parentVault == currentContract;
    assert MorphoMarketV1Adapter.morpho == MorphoMarketV1;

    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id marketId;
    (marketParams, marketId) = Utils.morphoMarketV1MarketParams(data);

    deallocate(e, MorphoMarketV1Adapter, data, assets);

    uint256 allocation = MorphoMarketV1Adapter.allocation(marketParams);
    uint256 supplyShares = MorphoMarketV1.position_(marketId, MorphoMarketV1Adapter).supplyShares;
    uint256 expected = Utils.expectedSupplyAssets(e, MorphoMarketV1, marketParams, supplyShares);

    assert allocation >= expected;
}
