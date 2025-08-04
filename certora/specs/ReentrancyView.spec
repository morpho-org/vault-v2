// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
persistent ghost bool staticCallAfterSStore;

// True when at least one slot is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

// Track storage changes.
hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterSStore) {
        staticCallUnsafe = true;
    }

}

// A STATICCAL is unsafe when the storage was changed before the call.
hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    if (storageChanged) {
        staticCallAfterSStore = true;
    }
}

rule reentrancyViewSafe(method f, env e, calldataarg data) {
    require (storageChanged == false, "setup ghost state");
    require (staticCallAfterSStore == false, "setup ghost state");
    require (staticCallUnsafe == false, "setup ghost state");

    f(e, data);

    assert !staticCallUnsafe;
}
