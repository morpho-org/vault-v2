// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
persistent ghost bool staticCallAfterSStore;

// True when at least one slot is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterSStore) {
        staticCallUnsafe = true;
    }
}

hook ALL_TSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterSStore) {
        staticCallUnsafe = true;
    }
}

// address(1) is ignored because it's the ecrecover function.
// These calls are assumed to not re-enter (documented). 0x56c07573 is realAssets() and 0xe4bb26f2 is isInRegistry(address).
hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    if (
        storageChanged
            && addr != 0x1
            && selector != 0x56c07573
            && selector != 0xe4bb26f2
            && selector != sig:balanceOf(address).selector
            && selector != sig:canReceiveShares(address).selector
            && selector != sig:canSendShares(address).selector
            && selector != sig:canReceiveAssets(address).selector
            && selector != sig:canSendAssets(address).selector
    ) {
        staticCallAfterSStore = true;
    }
}

// Check that static calls are either before the first store or after the last store.
rule reentrancyViewSafe(method f, env e, calldataarg data) {
    require(!storageChanged && !staticCallAfterSStore && !staticCallUnsafe, "set up the initial ghost state");
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
    assert !staticCallUnsafe;
}
