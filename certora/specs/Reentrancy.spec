// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Standard as ERC20;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Ignore changes done by accrueInterest; the state after this call is still valid even if it changed the state, as for the accrueInterest entry point.
    function accrueInterest() internal => NONDET;
}

// True when at least one slot of the vault was written.
persistent ghost bool storageChanged;

// True when at least one CALL to a contract other than the asset is executed after a storage change.
persistent ghost bool hasCallAfterStore;

// True when at least one slot of the vault is changed after a CALL is executed after a storage change.
persistent ghost bool unsafeCall;

hook ALL_SSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
    }
}

hook ALL_TSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
    }
}

// Calls to the asset are ignored: it is assumed to be a standard ERC20 token, that does not reenter.
hook CALL(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    if (storageChanged && addr != ERC20) {
        hasCallAfterStore = true;
    }
}

// Check that calls are either before the first store or after the last store (excluding the effects of accrueInterest and calls to the asset).
rule reentrancySafe(method f, env e, calldataarg data) {
    require(!storageChanged && !hasCallAfterStore && !unsafeCall, "set up the initial ghost state");
    if (f.selector == sig:forceDeallocate(address, bytes, uint256, address).selector) {
        address adapter;
        bytes adapterData;
        uint256 assets;
        address onBehalf;
    
        // Used to show that the penalty withdrawal does not deallocate again.
        require forceDeallocatePenalty(e, adapter) <= 10 ^ 18, "see forceDeallocatePenaltyBound in Invariants.spec";
        forceDeallocate(e, adapter, adapterData, assets, onBehalf);
    } else {
        f(e, data);
    }
    assert !unsafeCall;
}
