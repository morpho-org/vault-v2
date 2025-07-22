// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using MetaMorpho as MorphoVaultV1;
using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function _.extSloads(bytes32[]) external => NONDET DELETE;

    function MorphoVaultV1.previewRedeem(uint256) external returns uint256 envfree;
    function MorphoVaultV1Adapter.ids() external returns bytes32[] envfree;
    function MorphoVaultV1Adapter.shares() external returns uint256 envfree;
    function MorphoVaultV1Adapter.allocation() external returns uint256 envfree;

    function _.allocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoVaultV1AdapterWrapperSummary(e, true, data, assets) expect (bytes32[], uint256) ;
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoVaultV1AdapterWrapperSummary(e, false, data, assets) expect (bytes32[], uint256) ;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.idToMarketParams(MorphoHarness.Id) external => DISPATCHER(true);
    function _.market(MorphoHarness.Id) external => DISPATCHER(true);

    function Utils.expectedSupplyAssets(address, MorphoHarness.MarketParams, address) internal returns uint256;
    function _.expectedSupplyAssets(address, MorphoHarness.MarketParams marketParams, address user) external with (env e)
        => expectedSupplyAssetsSummary(e, marketParams, user) expect uint256;
}

persistent ghost uint256 ghostInterest;

function expectedSupplyAssetsSummary(env e, MorphoHarness.MarketParams marketParams, address user) returns uint256 {
    uint256 assets = Utils.expectedSupplyAssetsAlt(e, MorphoMarketV1, marketParams, user);
    return assets;
}

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

    require MorphoVaultV1Adapter.allocation() == MorphoVaultV1.previewRedeem(MorphoVaultV1Adapter.shares());

    // Ensure the VaultV2 and MorphoVaultV1 contracts are properly linked to the adapter in the conf file.
    assert MorphoVaultV1Adapter.parentVault == currentContract;
    assert MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1;

    bytes32[] adapterIds = MorphoVaultV1Adapter.ids();

    deallocate(e, MorphoVaultV1Adapter, data, assets);

    assert MorphoVaultV1Adapter.allocation() <= MorphoVaultV1.previewRedeem(require_uint256(MorphoVaultV1Adapter.shares()+1));

    assert forall uint i. i < adapterIds.length =>
        ghostAllocationAfter[adapterIds[i]] == ghostAllocationBefore[adapterIds[i]] + ghostInterest - assets;
    assert forall bytes32 id.
        !(exists uint i . i < adapterIds.length && id == adapterIds[i]) => ghostAllocationAfter[id] == ghostAllocationBefore[id];
}
