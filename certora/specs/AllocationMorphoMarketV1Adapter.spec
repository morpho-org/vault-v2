// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function _.extSloads(bytes32[]) external => NONDET DELETE;

    function MorphoMarketV1Adapter.ids(MorphoHarness.MarketParams) external returns bytes32[] envfree;
    function Utils.morphoMarketV1MarketParams(bytes) external returns (MorphoHarness.MarketParams,MorphoHarness.Id) envfree;

    function _.allocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoMarketV1AdapterWrapperSummary(e, true, data, assets) expect (bytes32[], uint256) ;
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoMarketV1AdapterWrapperSummary(e, false, data, assets) expect (bytes32[], uint256) ;

    function _.market(MorphoHarness.Id) external => DISPATCHER(true);
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
}

persistent ghost uint256 ghostInterest;

function morphoMarketV1AdapterWrapperSummary(env e, bool allocate, bytes data, uint256 assets) returns (bytes32[], uint256) {
    bytes32[] ids;
    uint256 interest;

    if (allocate) {
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
    require ghostAllocationAfter[id] == alloc;
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

    assert forall uint i. i < adapterIds.length =>
        ghostAllocationAfter[adapterIds[i]] == ghostAllocationBefore[adapterIds[i]] + ghostInterest + assets;
    assert forall bytes32 id.
        !(exists uint i . i < adapterIds.length && id == adapterIds[i]) => ghostAllocationAfter[id] == ghostAllocationBefore[id];
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

    assert forall uint i. i < adapterIds.length =>
        ghostAllocationAfter[adapterIds[i]] == ghostAllocationBefore[adapterIds[i]] + ghostInterest - assets;
    assert forall bytes32 id.
        !(exists uint i . i < adapterIds.length && id == adapterIds[i]) => ghostAllocationAfter[id] == ghostAllocationBefore[id];
}
