// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Interest accrual leaves the vault in the same state as the accrueInterest entry point, so its writes are not tracked.
    function accrueInterest() internal => summaryAccrueInterest();

    // Static calls, that can't write to the vault's storage.
    function _.realAssets() external => NONDET;
    function _.isInRegistry(address) external => NONDET;
    function _.canReceiveShares(address) external => NONDET;
    function _.canSendShares(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
    function _.canSendAssets(address) external => NONDET;

    // Adapters are arbitrary contracts.
    function _.allocate(bytes, uint256, bytes4, address) external => summaryAdapterCall(calledContract) expect(bytes32[], int256);
    function _.deallocate(bytes, uint256, bytes4, address) external => summaryAdapterCall(calledContract) expect(bytes32[], int256);
}

function summaryAccrueInterest() { }

function summaryAdapterCall(address adapter) returns (bytes32[], int256) {
    // Used to show that the penalty withdrawal of forceDeallocate does not deallocate again.
    require currentContract.forceDeallocatePenalty[adapter] <= 10 ^ 18, "see forceDeallocatePenaltyBound in Invariants.spec, the penalty is not written in entry points that call adapters";
    if (vaultStorageChanged) {
        adapterCalledAfterSStore = true;
    }
    bytes32[] ids;
    int256 change;
    return (ids, change);
}

// True when at least one slot of the vault was written.
persistent ghost bool vaultStorageChanged;

// True when an adapter was called after a write to the vault's storage.
persistent ghost bool adapterCalledAfterSStore;

// Number of writes to the vault's storage after an adapter was called after a write to the vault's storage.
persistent ghost mathint sstoreCount;

// Number of writes to caps allocations after an adapter was called after a write to the vault's storage.
persistent ghost mathint allocationSstoreCount;

hook ALL_SSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        vaultStorageChanged = true;
        if (adapterCalledAfterSStore) {
            sstoreCount = sstoreCount + 1;
        }
    }
}

hook Sstore currentContract.caps[KEY bytes32 id].allocation uint256 newValue (uint256 oldValue) {
    if (adapterCalledAfterSStore) {
        allocationSstoreCount = allocationSstoreCount + 1;
    }
}

// Check that adapters are called in a consistent state: either the vault wrote nothing before the call apart from interest accrual, or the vault writes nothing after the call apart from the caps allocations.
// Deposits through the liquidity adapter are in the second case: the adapter is called once the deposit is complete, and only the allocations remain to be updated.
rule adapterCalledInConsistentState(method f, env e, calldataarg data) {
    require !vaultStorageChanged, "setup ghost state";
    require !adapterCalledAfterSStore, "setup ghost state";
    require sstoreCount == 0, "setup ghost state";
    require allocationSstoreCount == 0, "setup ghost state";

    f(e, data);

    assert sstoreCount == allocationSstoreCount;
}
