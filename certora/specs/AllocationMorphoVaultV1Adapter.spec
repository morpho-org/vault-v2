// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using MetaMorpho as MorphoVaultV1;
using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function canReceiveShares(address) internal returns bool => ALWAYS(true);
    function canSendShares(address) internal returns bool => ALWAYS(true);
    function _.canReceiveShares(address) external => ALWAYS(true);

    function _.extSloads(bytes32[]) external => NONDET DELETE;
    function allocation(bytes32) external returns uint256 envfree;
    function MorphoVaultV1.totalSupply() external returns uint256 envfree;
    function MorphoVaultV1Adapter.ids() external returns bytes32[] envfree;
    function MorphoVaultV1Adapter.shares() external returns uint256 envfree;
    function MorphoVaultV1Adapter.allocation() external returns uint256 envfree;

    function _.allocate(bytes data, uint256 assets, bytes4 bs, address a) external with (env e)
        => morphoVaultV1AdapterWrapperSummary(e, true, data, assets, bs, a) expect (bytes32[], uint256);
    function _.deallocate(bytes data, uint256 assets, bytes4 bs, address a) external with (env e)
        => morphoVaultV1AdapterWrapperSummary(e, false, data, assets, bs, a) expect (bytes32[], uint256);
    function _.realizeLoss(bytes, bytes4, address) external => DISPATCHER(true);

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect uint256;
    function _.borrowRateView(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect uint256;

    function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns (uint256) => mulDivSummary(x,y,denominator);

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

function mulDivSummary(uint256 x, uint256 y, uint256 denominator) returns uint256 {
    mathint result;
    if (denominator == 0) revert();
    result = x * y / denominator;
    if (result >= 2^256) revert();
    return assert_uint256(result);
}

persistent ghost uint256 constantBorrowRate;

persistent ghost uint256 ghostInterest;

// Wrapper to record interest value returned by the adapter.
function morphoVaultV1AdapterWrapperSummary(env e, bool isAllocateCall, bytes data, uint256 assets, bytes4 bs, address a) returns (bytes32[], uint256) {
    bytes32[] ids;
    uint256 interest;

    if (isAllocateCall) {
        (ids, interest) = MorphoVaultV1Adapter.allocate(e, data, assets, bs, a);
    } else {
        (ids, interest) = MorphoVaultV1Adapter.deallocate(e, data, assets, bs, a);
    }

    ghostInterest = interest;

    return (ids, interest);
}

rule allocateMorphoVaultV1Adapter(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoVaultV1 == 0x10, "ack");
    require (MorphoVaultV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    // Ensure the VaultV2 and MorphoVaultV1 contracts are properly linked to the adapter in the conf file.
    assert MorphoVaultV1Adapter.parentVault == currentContract;
    assert MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1;

    bytes32[] adapterIds = MorphoVaultV1Adapter.ids();

    uint i;
    require i < adapterIds.length;

    bytes32 id;
    uint256 allocationBefore = allocation(id);
    uint256 idIAllocationBefore = allocation(adapterIds[i]);

    allocate(e, MorphoVaultV1Adapter, data, assets);

    assert allocation(adapterIds[i]) == idIAllocationBefore + ghostInterest + assets;
    assert !(exists uint j . j < adapterIds.length && id == adapterIds[j]) => allocation(id) == allocationBefore;
}

rule deallocateMorphoVaultV1Adapter(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoVaultV1 == 0x10, "ack");
    require (MorphoVaultV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    // Ensure the VaultV2 and MorphoVaultV1 contracts are properly linked to the adapter in the conf file.
    assert MorphoVaultV1Adapter.parentVault == currentContract;
    assert MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1;

    bytes32[] adapterIds = MorphoVaultV1Adapter.ids();

    uint i;
    require i < adapterIds.length;

    bytes32 id;
    uint256 allocationBefore = allocation(id);
    uint256 idIAllocationBefore = allocation(adapterIds[i]);

    deallocate(e, MorphoVaultV1Adapter, data, assets);

    assert allocation(adapterIds[i]) == idIAllocationBefore + ghostInterest - assets;
    assert !(exists uint j . j < adapterIds.length && id == adapterIds[j]) => allocation(id) == allocationBefore;
}

rule allocationEqExpectedAssets(env e, bytes data, uint256 assets) {
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

    realizeLoss(e, MorphoVaultV1Adapter, data);

    assert MorphoVaultV1Adapter.allocation() == MorphoVaultV1.previewRedeem(e, require_uint256(MorphoVaultV1Adapter.shares()));
}

rule allocationAfterDeallocate(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require (MorphoVaultV1 == 0x10, "ack");
    require (MorphoVaultV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");

    // Ensure the VaultV2 and MorphoVaultV1 contracts are properly linked to the adapter in the conf file.
    assert MorphoVaultV1Adapter.parentVault == currentContract;
    assert MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1;

    uint256 allocationBefore = MorphoVaultV1Adapter.allocation();
    uint256 expectedBefore = MorphoVaultV1.previewRedeem(e, require_uint256(MorphoVaultV1Adapter.shares()));

    require expectedBefore <= MorphoVaultV1.totalAssets(e);
    require allocationBefore == 0 => MorphoVaultV1Adapter.shares() == 0;

    require MorphoVaultV1.fee == 0;
    require e.block.timestamp <= max_uint64;

    deallocate(e, MorphoVaultV1Adapter, data, assets);

    // tentative hints
    assert ghostInterest != 0 => allocationBefore < expectedBefore;
    assert ghostInterest == 0 => allocationBefore >= expectedBefore;

    assert MorphoVaultV1Adapter.allocation() >= MorphoVaultV1.previewRedeem(e, require_uint256(MorphoVaultV1Adapter.shares()));
}
