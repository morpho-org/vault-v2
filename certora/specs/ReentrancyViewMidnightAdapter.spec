// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
persistent ghost bool staticCallAfterStore;

// True when at least one slot is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterStore) {
        staticCallUnsafe = true;
    }
}

hook ALL_TSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterStore) {
        staticCallUnsafe = true;
    }
}

// These calls are assumed to not re-enter (documented).
// 0xd4de4974 is Midnight's updatePositionView(Market,bytes32,address) and 0x1b14c072 is Midnight's liquidationLocked(bytes32,address).
hook STATICCALL(uint256 _, address _, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (storageChanged && selector != 0xd4de4974 && selector != 0x1b14c072) {
        staticCallAfterStore = true;
    }
}

// Check that static calls are either before the first store or after the last store.
rule reentrancyViewSafe(method f, env e, calldataarg data) {
    require(!storageChanged && !staticCallAfterStore && !staticCallUnsafe, "set up the initial ghost state");
    f(e, data);
    assert !staticCallUnsafe;
}
