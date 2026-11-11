// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one CALL is executed after a storage change.
persistent ghost bool hasCallAfterStore;

// True when at least one slot is changed after a CALL is executed after a storage change.
persistent ghost bool unsafeCall;

hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;
    if (hasCallAfterStore) {
        unsafeCall = true;
    }
}

// Transient slot 0 holds inForceDeallocate and admitting, which forceDeallocate sets right before Midnight's take so that the take's callbacks can read them.
hook ALL_TSTORE(uint loc, uint _) {
    if (loc != 0) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
    }
}

// This call is assumed to not re-enter (documented). 0xa6afed95 is the vault's accrueInterest().
hook CALL(uint256 _, address _, uint256 _, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (storageChanged && selector != 0xa6afed95) {
        hasCallAfterStore = true;
    }
}

// Check that calls are either before the first store or after the last store.
rule reentrancySafe(method f, env e, calldataarg data) {
    require(!storageChanged && !hasCallAfterStore && !unsafeCall, "set up the initial ghost state");
    f(e, data);
    assert !unsafeCall;
}
