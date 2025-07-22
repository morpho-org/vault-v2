// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using MetaMorpho as MorphoVaultV1;

methods {
    function _.extSloads(bytes32[]) external => NONDET DELETE;

    function MorphoVaultV1Adapter.ids() external returns bytes32[] envfree;

    function _.allocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoVaultV1AdapterWrapperSummary(e, true, data, assets) expect (bytes32[], uint256) ;
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoVaultV1AdapterWrapperSummary(e, false, data, assets) expect (bytes32[], uint256) ;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
}

persistent ghost uint256 ghostInterest;

function morphoVaultV1AdapterWrapperSummary(env e, bool allocate, bytes data, uint256 assets) returns (bytes32[], uint256) {
    bytes32[] ids;
    uint256 interest;

    if (allocate) {
        (ids, interest) = MorphoVaultV1Adapter.allocate(e, data, assets, _, _);
    } else {
        (ids, interest) = MorphoVaultV1Adapter.deallocate(e, data, assets, _, _);
    }

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

rule allocateMorphoVaultV1Adapter(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoVaultV1 == 0x10, "ack");
    require (MorphoVaultV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    require (forall bytes32 id . ghostAllocationBefore[id] == ghostAllocationAfter[id], "setup allocation before to be equal to allocation after");

    // Ensure the VaultV2 and MorphoVaultV1 contracts are properly linked to the adapter in the conf file.
    assert MorphoVaultV1Adapter.parentVault == currentContract;
    assert MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1;

    bytes32[] adapterIds = MorphoVaultV1Adapter.ids();

    allocate(e, MorphoVaultV1Adapter, data, assets);

    assert forall uint i. i < adapterIds.length =>
        ghostAllocationAfter[adapterIds[i]] == ghostAllocationBefore[adapterIds[i]] + ghostInterest + assets;
    assert forall bytes32 id.
        !(exists uint i . i < adapterIds.length && id == adapterIds[i]) => ghostAllocationAfter[id] == ghostAllocationBefore[id];
}

rule deallocateMorphoVaultV1Adapter(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoVaultV1 == 0x10, "ack");
    require (MorphoVaultV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    require (forall bytes32 id . ghostAllocationBefore[id] == ghostAllocationAfter[id], "setup allocation before to be equal to allocation after");

    // Ensure the VaultV2 and MorphoVaultV1 contracts are properly linked to the adapter in the conf file.
    assert MorphoVaultV1Adapter.parentVault == currentContract;
    assert MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1;

    bytes32[] adapterIds = MorphoVaultV1Adapter.ids();

    deallocate(e, MorphoVaultV1Adapter, data, assets);

    assert forall uint i. i < adapterIds.length =>
        ghostAllocationAfter[adapterIds[i]] == ghostAllocationBefore[adapterIds[i]] + ghostInterest - assets;
    assert forall bytes32 id.
        !(exists uint i . i < adapterIds.length && id == adapterIds[i]) => ghostAllocationAfter[id] == ghostAllocationBefore[id];
}
