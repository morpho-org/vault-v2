// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Standard as ERC20;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Ignore changes done by accrueInterest; the state after this call is still valid even if it changed the state, as for the accrueInterest entry point.
    // Its own static calls are made before its writes. When an accrual follows other writes (in allocateInternal for deposits, or in the penalty withdrawal of forceDeallocate), those writes complete an operation.
    function accrueInterest() internal => NONDET;

    // Ignore the consumption of the timelock; the state after this call is still valid, and it makes no external call.
    function timelocked() internal => NONDET;
}

// True when at least one slot of the vault was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL to a contract other than the asset is executed after a storage change.
persistent ghost bool staticCallAfterSStore;

// True when at least one slot of the vault is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

// Number of writes to the vault's storage.
persistent ghost mathint stores;

// Number of writes to caps allocations.
persistent ghost mathint allocationStores;

// True when a STATICCALL to a contract other than the asset is executed after a write that is not to the caps allocations.
persistent ghost bool staticCallAfterNonAllocationStore;

hook ALL_SSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        stores = stores + 1;
        if (staticCallAfterSStore) {
            staticCallUnsafe = true;
        }
    }
}

hook ALL_TSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        stores = stores + 1;
        if (staticCallAfterSStore) {
            staticCallUnsafe = true;
        }
    }
}

hook Sstore currentContract.caps[KEY bytes32 id].allocation uint256 newValue (uint256 oldValue) {
    allocationStores = allocationStores + 1;
}

// Calls to the asset are ignored: it is assumed to be a standard ERC20 token, that does not reenter.
// address(1) is ignored because it's the ecrecover precompile.
hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    if (addr != ERC20 && addr != 0x1) {
        if (storageChanged) {
            staticCallAfterSStore = true;
        }
        if (stores != allocationStores) {
            staticCallAfterNonAllocationStore = true;
        }
    }
}

// Check that static calls are either before the first store or after the last store (excluding the effects of accrueInterest and timelocked, and calls to the asset).
// forceDeallocate is checked separately, as it makes static calls in the penalty withdrawal after the deallocation.
rule reentrancyViewSafe(method f, env e, calldataarg data) filtered { f -> f.selector != sig:forceDeallocate(address, bytes, uint256, address).selector } {
    require(!storageChanged && !staticCallAfterSStore && !staticCallUnsafe, "set up the initial ghost state");
    f(e, data);
    assert !staticCallUnsafe;
}

// Check that forceDeallocate only writes the caps allocations before making static calls, so the static calls are made once the deallocation is complete.
rule forceDeallocateOnlyWritesAllocationsBeforeStaticCall(env e, address adapter, bytes data, uint256 assets, address onBehalf) {
    require(stores == 0 && allocationStores == 0 && !staticCallAfterNonAllocationStore, "set up the initial ghost state");
    forceDeallocate(e, adapter, data, assets, onBehalf);
    assert !staticCallAfterNonAllocationStore;
}
