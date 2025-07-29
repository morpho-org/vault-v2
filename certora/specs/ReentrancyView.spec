// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// Execution is divided into phases; each STATICCALL starts a new one.
persistent ghost mathint currentPhase;

// Last phase in which every storage slot was accessed (SLOAD or SSTORE)
persistent ghost mapping(uint => mathint) lastTouchedPhase;

// True when at least one slot was written after a later STATICCALL
persistent ghost bool hasReentrancyUnsafeCall;

// Any read marks the slot’s latest phase
hook ALL_SLOAD(uint loc)  uint v {
    lastTouchedPhase[loc] = currentPhase;
}

// A write is unsafe when the slot was last touched in an earlier phase
hook ALL_SSTORE(uint loc, uint v) {
    if (lastTouchedPhase[loc] < currentPhase) {
        hasReentrancyUnsafeCall = true;
    }
    lastTouchedPhase[loc] = currentPhase;
}

// Update the phase number
hook STATICCALL(uint g, address addr, uint argsOffset, uint argsLength, uint retOffset,  uint retLength) uint rc {
    currentPhase = currentPhase + 1;
}

rule reentrancyViewSafe(method f, env e, calldataarg data) {

    require forall uint loc. lastTouchedPhase[loc] == max_uint256;
    require currentPhase == 0;
    require hasReentrancyUnsafeCall == false;

    f(e, data);

    assert !hasReentrancyUnsafeCall;
}
