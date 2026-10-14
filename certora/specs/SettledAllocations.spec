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

// Number of allocation writes the vault still has to do to apply the last adapter allocate or deallocate.
persistent ghost mathint pendingAllocationWrites;

persistent ghost bool adapterCalledWithPendingWrites;

hook Sstore caps[KEY bytes32 id].allocation uint256 newAllocation {
    pendingAllocationWrites = pendingAllocationWrites - 1;
}

function checkSettledAllocations() {
    if (pendingAllocationWrites != 0) {
        adapterCalledWithPendingWrites = true;
    }
}

function adapterUpdateSummary() returns (bytes32[], int256) {
    checkSettledAllocations();
    bytes32[] ids;
    int256 change;
    pendingAllocationWrites = ids.length;
    return (ids, change);
}

function adapterRealAssetsSummary() returns uint256 {
    checkSettledAllocations();
    uint256 value;
    return value;
}

// Check that adapters are only called when the allocations are settled, so that adapters can read allocations during allocate, deallocate and realAssets. Also check that allocations are settled at the end, which justifies deleting multicall.
rule adaptersAreCalledWithSettledAllocations(method f, env e, calldataarg data) {
    require(pendingAllocationWrites == 0 && !adapterCalledWithPendingWrites, "set up the initial ghost state");
    f(e, data);
    assert !adapterCalledWithPendingWrites;
    assert pendingAllocationWrites == 0;
}
