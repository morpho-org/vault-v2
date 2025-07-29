// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function MorphoMarketV1.totalSupplyAssets(MorphoHarness.Id) external returns uint256 envfree;
    function MorphoMarketV1.totalSupplyShares(MorphoHarness.Id) external returns uint256 envfree;
    function MorphoMarketV1Adapter.ids(MorphoHarness.MarketParams) external returns bytes32[] envfree;
    function MorphoMarketV1Adapter.shares(MorphoHarness.Id) external returns uint256 envfree;
    function MorphoMarketV1Adapter.allocation(MorphoHarness.MarketParams) external returns uint256 envfree;
    function Utils.morphoMarketV1MarketParams(bytes) external returns (MorphoHarness.MarketParams, MorphoHarness.Id) envfree;

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;

    function _.allocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoMarketV1AdapterWrapperSummary(e, true, data, assets) expect (bytes32[], uint256);
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoMarketV1AdapterWrapperSummary(e, false, data, assets) expect (bytes32[], uint256);

    function _.realizeLoss(bytes, bytes4, address) external => DISPATCHER(true);
    function _.market(MorphoHarness.Id) external => DISPATCHER(true);
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
}

persistent ghost uint256 ghostInterest;

// Wrapper to record interest value returned by the adapter and ensure returned ids are unique.
function morphoMarketV1AdapterWrapperSummary(env e, bool isAllocateCall, bytes data, uint256 assets) returns (bytes32[], uint256) {
    bytes32[] ids;
    uint256 interest;

    if (isAllocateCall) {
        (ids, interest) = MorphoMarketV1Adapter.allocate(e, data, assets, _, _);
    } else {
        (ids, interest) = MorphoMarketV1Adapter.deallocate(e, data, assets, _, _);
    }

    require (forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "assume that all returned ids are unique");
    ghostInterest = interest;

    return (ids, interest);
}

// Ghost copy of caps[*].allocation that holds values before calls to be able to use quantifiers.
persistent ghost mapping(bytes32 => uint256) ghostAllocationBefore {
    init_state axiom forall bytes32 id. ghostAllocationBefore[id] == 0;
}

// Ghost copy of caps[*].allocation that holds values after calls to be able to use quantifiers.
persistent ghost mapping(bytes32 => uint256) ghostAllocationAfter {
    init_state axiom forall bytes32 id. ghostAllocationAfter[id] == 0;
}

hook Sload uint256 alloc caps[KEY bytes32 id].allocation {
    require (ghostAllocationAfter[id] == alloc, "require the ghost copy to be equal to the concrete value");
 }

hook Sstore caps[KEY bytes32 id].allocation uint256 newAllocation (uint256 _) {
    ghostAllocationAfter[id] = newAllocation;
}

rule allocateMorphoMarketV1Adapter(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    require (forall bytes32 id . ghostAllocationBefore[id] == ghostAllocationAfter[id], "setup allocation before to be equal to allocation after");

    MorphoHarness.MarketParams marketParams;
    (marketParams, _) = Utils.morphoMarketV1MarketParams(data);

    // Ensure the VaultV2 and Morpho contracts are properly linked to the adapter in the conf file.
    assert MorphoMarketV1Adapter.parentVault == currentContract;
    assert MorphoMarketV1Adapter.morpho == MorphoMarketV1;

    bytes32[] adapterIds = MorphoMarketV1Adapter.ids(marketParams);

    allocate(e, MorphoMarketV1Adapter, data, assets);

    assert forall uint i. i < adapterIds.length => ghostAllocationAfter[adapterIds[i]] == ghostAllocationBefore[adapterIds[i]] + ghostInterest + assets;
    assert forall bytes32 id. !(exists uint i . i < adapterIds.length && id == adapterIds[i]) => ghostAllocationAfter[id] == ghostAllocationBefore[id];
}

rule allocateMorphoMarketV1AdapterAllocationVsExpectedAssets(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id marketId;
    (marketParams, marketId) = Utils.morphoMarketV1MarketParams(data);

    require (MorphoMarketV1Adapter.allocation(marketParams) <= MorphoMarketV1.totalSupplyAssets(marketId), "assume the adapter's allocation are less than or equal to the total assets");
    require (MorphoMarketV1Adapter.shares(marketId) <= MorphoMarketV1.totalSupplyShares(marketId), "assume the adapter's shares are less than or equal to the total shares");

    // Ensure the VaultV2 and Morpho contracts are properly linked to the adapter in the conf file.
    assert MorphoMarketV1Adapter.parentVault == currentContract;
    assert MorphoMarketV1Adapter.morpho == MorphoMarketV1;

    allocate(e, MorphoMarketV1Adapter, data, assets);
    realizeLoss(e, MorphoMarketV1Adapter, data);

    assert MorphoMarketV1Adapter.allocation(marketParams) == Utils.expectedSupplyAssets(e, MorphoMarketV1, marketParams, MorphoMarketV1Adapter.shares(marketId));
}

rule deallocateMorphoMarketV1Adapter(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    require (forall bytes32 id . ghostAllocationBefore[id] == ghostAllocationAfter[id], "setup allocation before to be equal to allocation after");

    MorphoHarness.MarketParams marketParams;
    (marketParams, _) = Utils.morphoMarketV1MarketParams(data);

    // Ensure the VaultV2 and Morpho contracts are properly linked to the adapter in the conf file.
    assert MorphoMarketV1Adapter.parentVault == currentContract;
    assert MorphoMarketV1Adapter.morpho == MorphoMarketV1;

    bytes32[] adapterIds = MorphoMarketV1Adapter.ids(marketParams);

    deallocate(e, MorphoMarketV1Adapter, data, assets);

    assert forall uint i. i < adapterIds.length => ghostAllocationAfter[adapterIds[i]] == ghostAllocationBefore[adapterIds[i]] + ghostInterest - assets;
    assert forall bytes32 id. (forall uint i . i >= adapterIds.length || id != adapterIds[i]) => ghostAllocationAfter[id] == ghostAllocationBefore[id];
}

rule deallocateMorphoMarketV1AdapterAllocationVsExpectedAssets(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    MorphoHarness.MarketParams marketParams;
    MorphoHarness.Id marketId;
    (marketParams, marketId) = Utils.morphoMarketV1MarketParams(data);

    require (MorphoMarketV1Adapter.allocation(marketParams) <= MorphoMarketV1.totalSupplyAssets(marketId), "assume the adapter's allocation is less than or equal to the total assets");
    require (MorphoMarketV1Adapter.shares(marketId) <= MorphoMarketV1.totalSupplyShares(marketId), "assume the adapter's shares are less than or equal to the total shares");

    // Ensure the VaultV2 and Morpho contracts are properly linked to the adapter in the conf file.
    assert MorphoMarketV1Adapter.parentVault == currentContract;
    assert MorphoMarketV1Adapter.morpho == MorphoMarketV1;

    deallocate(e, MorphoMarketV1Adapter, data, assets);
    realizeLoss(e, MorphoMarketV1Adapter, data);

    assert MorphoMarketV1Adapter.allocation(marketParams) == Utils.expectedSupplyAssets(e, MorphoMarketV1, marketParams, MorphoMarketV1Adapter.shares(marketId));
}
