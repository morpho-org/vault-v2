// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function allocation(bytes32) external returns uint256 envfree;

    function MorphoMarketV1Adapter.ids(MorphoHarness.MarketParams) external returns (bytes32[]) envfree;
    function MorphoMarketV1Adapter.allocation(MorphoHarness.MarketParams) external returns (uint256) envfree;

    function Utils.decodeMarketParams(bytes) external returns (MorphoHarness.MarketParams) envfree;
    function Utils.id(MorphoHarness.MarketParams) external returns (MorphoHarness.Id) envfree;

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect(uint256);
    function _.borrowRateView(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect(uint256);

    function _.allocate(bytes data, uint256 assets, bytes4 bs, address a) external with(env e) => morphoMarketV1AdapterWrapperSummary(e, true, data, assets, bs, a) expect(bytes32[], int256);
    function _.deallocate(bytes data, uint256 assets, bytes4 bs, address a) external with(env e) => morphoMarketV1AdapterWrapperSummary(e, false, data, assets, bs, a) expect(bytes32[], int256);

    function _.position(MorphoHarness.Id, address) external => DISPATCHER(true);
    function _.market(MorphoHarness.Id) external => DISPATCHER(true);

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

strong invariant allocationIsInt256(bytes32 id)
    allocation(id) <= max_int256();

persistent ghost uint256 constantBorrowRate;

persistent ghost int256 ghostChange;

// Wrapper to record change returned by the adapter and ensure returned ids are unique.
function morphoMarketV1AdapterWrapperSummary(env e, bool isAllocateCall, bytes data, uint256 assets, bytes4 bs, address a) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    if (isAllocateCall) {
        ids, change = MorphoMarketV1Adapter.allocate(e, data, assets, bs, a);
    } else {
        ids, change = MorphoMarketV1Adapter.deallocate(e, data, assets, bs, a);
    }
    require forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "proven in the distinctMarketV1AdapterIds rule";
    ghostChange = change;

    return (ids, change);
}

rule allocateChangesAdapterIds(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require MorphoMarketV1 == 0x10, "ack";
    require MorphoMarketV1Adapter == 0x11, "ack";
    require currentContract == 0x12, "ack";

    MorphoHarness.MarketParams marketParams = Utils.decodeMarketParams(data);
    bytes32[] adapterIds = MorphoMarketV1Adapter.ids(marketParams);

    bytes32 id;
    uint256 allocationBefore = allocation(id);

    uint i;
    require i < adapterIds.length, "require i to be a valid index";
    requireInvariant allocationIsInt256(adapterIds[i]);
    int256 idIAllocationBefore = assert_int256(allocation(adapterIds[i]));

    allocate(e, MorphoMarketV1Adapter, data, assets);

    assert allocation(adapterIds[i]) == idIAllocationBefore + ghostChange;
    assert !(exists uint j. j < adapterIds.length && id == adapterIds[j]) => currentContract.caps[id].allocation == allocationBefore;
}

rule allocationAfterAllocate(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require MorphoMarketV1 == 0x10, "ack";
    require MorphoMarketV1Adapter == 0x11, "ack";
    require currentContract == 0x12, "ack";

    allocate(e, MorphoMarketV1Adapter, data, assets);

    MorphoHarness.MarketParams marketParams = Utils.decodeMarketParams(data);
    uint256 allocation = MorphoMarketV1Adapter.allocation(marketParams);
    uint256 expected = Utils.expectedSupplyAssets(e, MorphoMarketV1, marketParams, MorphoMarketV1Adapter);

    assert allocation == expected;
}

rule deallocateChangesAdapterIds(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require MorphoMarketV1 == 0x10, "ack";
    require MorphoMarketV1Adapter == 0x11, "ack";
    require currentContract == 0x12, "ack";

    MorphoHarness.MarketParams marketParams = Utils.decodeMarketParams(data);
    bytes32[] adapterIds = MorphoMarketV1Adapter.ids(marketParams);

    bytes32 id;
    uint256 allocationBefore = allocation(id);

    uint i;
    require i < adapterIds.length, "require i to be a valid index";
    requireInvariant allocationIsInt256(adapterIds[i]);
    int256 idIAllocationBefore = assert_int256(allocation(adapterIds[i]));

    deallocate(e, MorphoMarketV1Adapter, data, assets);

    assert allocation(adapterIds[i]) == idIAllocationBefore + ghostChange;
    assert !(exists uint j. j < adapterIds.length && id == adapterIds[j]) => currentContract.caps[id].allocation == allocationBefore;
}

rule allocationAfterDeallocate(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require MorphoMarketV1 == 0x10, "ack";
    require MorphoMarketV1Adapter == 0x11, "ack";
    require currentContract == 0x12, "ack";

    deallocate(e, MorphoMarketV1Adapter, data, assets);

    MorphoHarness.MarketParams marketParams = Utils.decodeMarketParams(data);
    uint256 allocation = MorphoMarketV1Adapter.allocation(marketParams);
    uint256 expected = Utils.expectedSupplyAssets(e, MorphoMarketV1, marketParams, MorphoMarketV1Adapter);

    assert allocation == expected;
}
