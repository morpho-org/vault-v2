// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Standard as ERC20;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// True when at least one slot of the vault was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL to a contract other than the asset is executed after a storage change.
persistent ghost bool staticCallAfterSStore;

// True when at least one slot of the vault is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

hook ALL_SSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (staticCallAfterSStore) {
            staticCallUnsafe = true;
        }
    }
}

hook ALL_TSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (staticCallAfterSStore) {
            staticCallUnsafe = true;
        }
    }
}

// Calls to the asset are ignored: it is assumed to be a standard ERC20 token, that does not reenter.
// address(1) is ignored because it's the ecrecover precompile.
hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    if (storageChanged && addr != ERC20 && addr != 0x1) {
        staticCallAfterSStore = true;
    }
}

// Check that static calls are either before the first store or after the last store (excluding calls to the asset).
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
