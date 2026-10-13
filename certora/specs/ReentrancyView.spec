// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // These calls are assumed to not re-enter (documented).
    function _.realAssets() external => ignoredUintStaticcall() expect(uint256);
    function _.balanceOf(address) external => ignoredUintStaticcall() expect(uint256);
    function _.isInRegistry(address) external => ignoredBoolStaticcall() expect(bool);
    function _.canReceiveShares(address) external => ignoredBoolStaticcall() expect(bool);
    function _.canSendShares(address) external => ignoredBoolStaticcall() expect(bool);
    function _.canReceiveAssets(address) external => ignoredBoolStaticcall() expect(bool);
    function _.canSendAssets(address) external => ignoredBoolStaticcall() expect(bool);
}

function ignoredUintStaticcall() returns uint256 {
    ignoredStaticcall = true;
    uint256 value;
    return value;
}

function ignoredBoolStaticcall() returns bool {
    ignoredStaticcall = true;
    bool value;
    return value;
}

// True when the next STATICCALL is a call to one of the functions assumed to not reenter.
persistent ghost bool ignoredStaticcall;

// True when at least one slot of the vault was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
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

// address(1) is ignored because it's the ecrecover precompile.
hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    if (!ignoredStaticcall && storageChanged && addr != 0x1) {
        staticCallAfterSStore = true;
    }
    ignoredStaticcall = false;
}

// Check that static calls are either before the first store or after the last store.
rule reentrancyViewSafe(method f, env e, calldataarg data) {
    require(!ignoredStaticcall && !storageChanged && !staticCallAfterSStore && !staticCallUnsafe, "set up the initial ghost state");
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
