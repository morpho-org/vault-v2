// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using MetaMorpho as MorphoVaultV1;
using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function MorphoVaultV1.totalSupply() external returns uint256 envfree;
    function MorphoVaultV1Adapter.ids() external returns bytes32[] envfree;
    function MorphoVaultV1Adapter.shares() external returns uint256 envfree;
    function MorphoVaultV1Adapter.allocation() external returns uint256 envfree;

    function _.allocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoVaultV1AdapterWrapperSummary(e, true, data, assets) expect (bytes32[], uint256) ;
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external with (env e)
        => morphoVaultV1AdapterWrapperSummary(e, false, data, assets) expect (bytes32[], uint256) ;
    function _.realizeLoss(bytes, bytes4, address) external => DISPATCHER(true);

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

    // Dispatched for performance reasons.
    function _.market(MorphoHarness.Id) external => DISPATCHER(true);
    function _.idToMarketParams(MorphoHarness.Id) external => DISPATCHER(true);
    function _.position(MorphoHarness.Id, address) external => DISPATCHER(true);
    function _.supplyShares(MorphoHarness.Id, address) external => DISPATCHER(true);
    function _.accrueInterest(MorphoHarness.MarketParams) external => DISPATCHER(true);
    function _.supply(MorphoHarness.MarketParams, uint256, uint256, address, bytes) external => DISPATCHER(true);
    function _.withdraw(MorphoHarness.MarketParams, uint256, uint256, address, address) external => DISPATCHER(true);
}

persistent ghost uint256 ghostInterest;

// Wrapper to record interest value returned by the adapter.
function morphoVaultV1AdapterWrapperSummary(env e, bool isAllocateCall, bytes data, uint256 assets) returns (bytes32[], uint256) {
    bytes32[] ids;
    uint256 interest;

    if (isAllocateCall) {
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

    assert forall uint i. i < adapterIds.length => ghostAllocationAfter[adapterIds[i]] == ghostAllocationBefore[adapterIds[i]] + ghostInterest + assets;
    assert forall bytes32 id. !(exists uint i . i < adapterIds.length && id == adapterIds[i]) => ghostAllocationAfter[id] == ghostAllocationBefore[id];
}

rule allocateMorphoVaultV1AdapterAllocationVsExpectedAssets(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoVaultV1 == 0x10, "ack");
    require (MorphoVaultV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");
    require (MorphoMarketV1 == 0x13, "ack");

    // Ensure the VaultV2 and MorphoVaultV1 contracts are properly linked to the adapter in the conf file.
    assert MorphoVaultV1Adapter.parentVault == currentContract;
    assert MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1;
    // Not linked in the conf for perofrmance reasons.
    require (MorphoVaultV1.MORPHO == MorphoMarketV1, "require MorphoVaultV1's MORPHO to be MorphoMarketV1");

    require (MorphoVaultV1.fee == 0, "assume the performance fee is null in MorphoVaultV1");
    require (MorphoVaultV1Adapter.allocation() <= MorphoVaultV1.totalAssets(e), "assume the adapter's allocation are less than or equal to the total assets");
    require (MorphoVaultV1Adapter.shares() <= MorphoVaultV1.totalSupply(), "assume the adapter's shares are less than or equal to the total shares");

    allocate(e, MorphoVaultV1Adapter, data, assets);
    realizeLoss(e, MorphoVaultV1Adapter, data);

    assert MorphoVaultV1Adapter.allocation() == MorphoVaultV1.previewRedeem(e, require_uint256(MorphoVaultV1Adapter.shares()));
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

rule deallocateMorphoVaultV1AdapterAllocationVsExpectedAssets(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoVaultV1 == 0x10, "ack");
    require (MorphoVaultV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");
    require (MorphoMarketV1 == 0x13, "ack");

    // Ensure the VaultV2 and MorphoVaultV1 contracts are properly linked to the adapter in the conf file.
    assert MorphoVaultV1Adapter.parentVault == currentContract;
    assert MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1;
    // Not linked in the conf for perofrmance reasons.
    require (MorphoVaultV1.MORPHO == MorphoMarketV1, "require MorphoVaultV1's MORPHO to be MorphoMarketV1");

    require (MorphoVaultV1.fee == 0, "assume the performance fee is null in MorphoVaultV1");
    require (MorphoVaultV1Adapter.allocation() <= MorphoVaultV1.totalAssets(e), "assume the adapter's allocation are less than or equal to the total assets");
    require (MorphoVaultV1Adapter.shares() <= MorphoVaultV1.totalSupply(), "assume the adapter's shares are less than or equal to the total shares");

    deallocate(e, MorphoVaultV1Adapter, data, assets);
    realizeLoss(e, MorphoVaultV1Adapter, data);

    assert MorphoVaultV1Adapter.allocation() == MorphoVaultV1.previewRedeem(e, require_uint256(MorphoVaultV1Adapter.shares()));
}
