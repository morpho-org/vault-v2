// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// VaultV2 and Midnight are in the scene only to name the selectors of the ignored calls. They are not linked, so the calls of the adapter stay unresolved.
using VaultV2 as VaultV2;
using Midnight as Midnight;

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

// Writes to transient slot 0 are ignored. This slot holds inForceDeallocate and admitting.
// A force deallocation sets them before Midnight's take, because the callbacks of this take read them, and it stores the net credit after the take.
hook ALL_TSTORE(uint loc, uint _) {
    if (loc != 0) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
    }
}

// These two calls are assumed to not re-enter the adapter.
// The vault's accrueInterest only makes static calls. onBuy calls it after it sets the in-progress buy and before it clears it.
// Midnight's withdraw only calls the loan token, required to be the vault's asset. A self-funded onBuy calls it after it stores the bought market and before it stores the net credit of the funding market.
hook CALL(uint256 _, address _, uint256 _, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (storageChanged && selector != sig:VaultV2.accrueInterest().selector && selector != sig:Midnight.withdraw(Midnight.Market, uint256, address, address).selector) {
        hasCallAfterStore = true;
    }
}

// Check that calls are either before the first store or after the last store.
rule reentrancySafe(method f, env e, calldataarg data) {
    require(!storageChanged && !hasCallAfterStore && !unsafeCall, "set up the initial ghost state");
    f(e, data);
    assert !unsafeCall;
}
