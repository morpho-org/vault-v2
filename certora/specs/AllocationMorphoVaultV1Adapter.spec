// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using MetaMorpho as MorphoVaultV1;
using MorphoHarness as MorphoMarketV1;

methods {
    function _.extSloads(bytes32[]) external => NONDET DELETE;

    function MorphoVaultV1.totalSupply() external returns (uint256) envfree;
    function MorphoVaultV1.balanceOf(address) external returns (uint256) envfree;
    function MorphoVaultV1Adapter.ids() external returns (bytes32[]) envfree;
    function MorphoVaultV1Adapter.allocation() external returns (uint256) envfree;
    function MorphoMarketV1.supplyShares(MorphoHarness.Id, address) external returns (uint256) envfree;

    function _.allocate(bytes data, uint256 assets, bytes4 bs, address a) external with(env e) => morphoVaultV1AdapterWrapperSummary(e, true, data, assets, bs, a) expect(bytes32[], int256);
    function _.deallocate(bytes data, uint256 assets, bytes4 bs, address a) external with(env e) => morphoVaultV1AdapterWrapperSummary(e, false, data, assets, bs, a) expect(bytes32[], int256);

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect(uint256);
    function _.borrowRateView(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect(uint256);

    function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns (uint256) => mulDivSummary(x, y, denominator);
    function _.supplyShares(address, MorphoHarness.Id id, address user) internal => summarySupplyShares(id, user) expect uint256;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

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
    if (result >= 2 ^ 256) revert();
    return assert_uint256(result);
}


function summarySupplyShares(MorphoHarness.Id id, address user) returns uint256 {
    return MorphoMarketV1.supplyShares(id, user);
}

persistent ghost uint256 constantBorrowRate;

persistent ghost int256 ghostChange;

// Wrapper to record change returned by the adapter.
function morphoVaultV1AdapterWrapperSummary(env e, bool isAllocateCall, bytes data, uint256 assets, bytes4 bs, address a) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    if (isAllocateCall) {
        ids, change = MorphoVaultV1Adapter.allocate(e, data, assets, bs, a);
    } else {
        ids, change = MorphoVaultV1Adapter.deallocate(e, data, assets, bs, a);
    }

    ghostChange = change;

    return (ids, change);
}

rule allocateChangesAdapterIds(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require MorphoVaultV1 == 0x10, "ack";
    require MorphoVaultV1Adapter == 0x11, "ack";
    require currentContract == 0x12, "ack";

    bytes32[] adapterIds = MorphoVaultV1Adapter.ids();

    bytes32 id;
    uint256 allocationBefore = allocation(id);

    uint i;
    require i < adapterIds.length, "require i to be a valid index";
    requireInvariant allocationIsInt256(adapterIds[i]);
    int256 idIAllocationBefore = assert_int256(allocation(adapterIds[i]));

    allocate(e, MorphoVaultV1Adapter, data, assets);

    assert allocation(adapterIds[i]) == idIAllocationBefore + ghostChange;
    assert !(exists uint j. j < adapterIds.length && id == adapterIds[j]) => currentContract.caps[id].allocation == allocationBefore;
}

rule allocationAfterAllocate(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require MorphoVaultV1 == 0x10, "ack";
    require MorphoVaultV1Adapter == 0x11, "ack";
    require currentContract == 0x12, "ack";

    allocate(e, MorphoVaultV1Adapter, data, assets);

    assert MorphoVaultV1Adapter.allocation() == MorphoVaultV1.previewRedeem(e, MorphoVaultV1.balanceOf(MorphoVaultV1Adapter));
}

rule deallocateChangesAdapterIds(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require MorphoVaultV1 == 0x10, "ack";
    require MorphoVaultV1Adapter == 0x11, "ack";
    require currentContract == 0x12, "ack";
    require currentContract.asset == 0x13, "ack";

    bytes32[] adapterIds = MorphoVaultV1Adapter.ids();

    bytes32 id;
    uint256 allocationBefore = allocation(id);

    uint i;
    require i < adapterIds.length, "require i to be a valid index";
    requireInvariant allocationIsInt256(adapterIds[i]);
    int256 idIAllocationBefore = assert_int256(allocation(adapterIds[i]));

    deallocate(e, MorphoVaultV1Adapter, data, assets);

    assert allocation(adapterIds[i]) == idIAllocationBefore + ghostChange;
    assert !(exists uint j. j < adapterIds.length && id == adapterIds[j]) => currentContract.caps[id].allocation == allocationBefore;
}

rule allocationAfterDeallocate(env e, bytes data, uint256 assets) {
    // Trick to require that all the following addresses are different.
    require MorphoVaultV1 == 0x10, "ack";
    require MorphoVaultV1Adapter == 0x11, "ack";
    require currentContract == 0x12, "ack";
    require currentContract.asset == 0x13, "ack";

    requireInvariant allocationIsInt256(MorphoVaultV1Adapter.adapterId);

    deallocate(e, MorphoVaultV1Adapter, data, assets);

    assert MorphoVaultV1Adapter.allocation() == MorphoVaultV1.previewRedeem(e, MorphoVaultV1.balanceOf(MorphoVaultV1Adapter));
}
