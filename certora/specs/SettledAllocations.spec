// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.allocate(bytes, uint256, bytes4, address) external => adapterUpdateSummary() expect(bytes32[], int256);
    function _.deallocate(bytes, uint256, bytes4, address) external => adapterUpdateSummary() expect(bytes32[], int256);
    function _.realAssets() external => adapterRealAssetsSummary() expect(uint256);

    function _.balanceOf(address) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.isInRegistry(address) external => NONDET;
    function _.canReceiveShares(address) external => NONDET;
    function _.canSendShares(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
}

// Ids returned by the last adapter allocate or deallocate.
persistent ghost mapping(uint256 => bytes32) returnedIds;

persistent ghost uint256 returnedIdsLength;

// Whether the vault wrote the allocation of the id since the last adapter allocate or deallocate.
persistent ghost mapping(bytes32 => bool) allocationWritten;

persistent ghost bool adapterCalledWithPendingWrites;

hook Sstore caps[KEY bytes32 id].allocation uint256 newAllocation {
    allocationWritten[id] = true;
}

definition allocationsSettled() returns bool = forall uint256 i. i < returnedIdsLength => allocationWritten[returnedIds[i]];

function checkSettledAllocations() {
    if (!allocationsSettled()) {
        adapterCalledWithPendingWrites = true;
    }
}

function adapterUpdateSummary() returns (bytes32[], int256) {
    checkSettledAllocations();
    bytes32[] ids;
    int256 change;
    havoc returnedIds assuming forall uint256 i. i < ids.length => returnedIds@new[i] == ids[i];
    returnedIdsLength = ids.length;
    havoc allocationWritten assuming forall bytes32 id. !allocationWritten@new[id];
    return (ids, change);
}

function adapterRealAssetsSummary() returns uint256 {
    checkSettledAllocations();
    uint256 value;
    return value;
}

// Check that the vault writes the allocation of every id returned by an adapter before calling an adapter again, so that adapters can read allocations during allocate, deallocate and realAssets. Also check that allocations are settled at the end, which justifies deleting multicall.
rule adaptersAreCalledWithSettledAllocations(method f, env e, calldataarg data) {
    require(returnedIdsLength == 0 && !adapterCalledWithPendingWrites, "set up the initial ghost state");
    f(e, data);
    assert !adapterCalledWithPendingWrites;
    assert allocationsSettled();
}
