// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function lastUpdate() external returns uint64 envfree;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

// Track storage changes.
hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;

}

// A STATICCAL is unsafe when the storage was changed before the call.
hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    if (storageChanged) {
        staticCallUnsafe = true;
    }
}

rule reentrancyViewSafe(method f, env e, calldataarg data) {
    require (storageChanged == false, "setup ghost state");
    require (staticCallUnsafe == false, "setup ghost state");

    require lastUpdate() == e.block.timestamp;

    f(e, data);

    assert storageChanged => !staticCallUnsafe;
}
