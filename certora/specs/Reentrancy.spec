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

// True when at least one CALL to a contract other than the asset is executed.
persistent ghost bool hasCall;

// Number of writes to the vault's storage after a CALL to a contract other than the asset.
persistent ghost mathint storesAfterCall;

// Number of writes to caps allocations after a CALL to a contract other than the asset.
persistent ghost mathint allocationStoresAfterCall;

hook ALL_SSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
        if (hasCall) {
            storesAfterCall = storesAfterCall + 1;
        }
    }
}

hook ALL_TSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
        if (hasCall) {
            storesAfterCall = storesAfterCall + 1;
        }
    }
}

// Calls to the asset are ignored: it is assumed to be a standard ERC20 token, that does not reenter.
hook CALL(uint256 _, address addr, uint256 _, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (addr != ERC20) {
        hasCall = true;
        if (storageChanged) {
            hasCallAfterStore = true;
        }
    }
}

hook Sstore currentContract.caps[KEY bytes32 _].allocation uint256 _ {
    if (hasCall) {
        allocationStoresAfterCall = allocationStoresAfterCall + 1;
    }
}

// Check that calls are either before the first store or after the last store (excluding the effects of accrueInterest and calls to the asset).
// Deposits are checked separately, as they call the liquidity adapter after creating the shares.
rule reentrancySafe(method f, env e, calldataarg data) filtered { f -> f.selector != sig:deposit(uint256, address).selector && f.selector != sig:mint(uint256, address).selector } {
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

// Check that deposits only write the caps allocations after calling the liquidity adapter, so the adapter is called once the deposit is complete.
rule depositOnlyWritesAllocationsAfterCall(method f, env e, calldataarg data) filtered { f -> f.selector == sig:deposit(uint256, address).selector || f.selector == sig:mint(uint256, address).selector } {
    require(!hasCall && storesAfterCall == 0 && allocationStoresAfterCall == 0, "set up the initial ghost state");
    f(e, data);
    assert storesAfterCall == allocationStoresAfterCall;
}
