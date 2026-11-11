// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using MorphoMarketV1RegistryV2 as MorphoMarketV1RegistryV2;

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
// These calls are assumed to not re-enter (documented).
hook STATICCALL(uint256 _, address addr, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (
        storageChanged
            && addr != 0x1
            && selector != sig:MorphoMarketV1AdapterV2.realAssets().selector
            && selector != sig:MorphoMarketV1RegistryV2.isInRegistry(address).selector
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
