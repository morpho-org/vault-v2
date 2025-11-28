// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using EarliestTime as EarliestTime;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function EarliestTime.getSelector(bytes) external returns bytes4 envfree;
    function EarliestTime.extractDecreaseTimelockArgs(bytes) external returns (bytes4, uint256) envfree;
}

// Ghost to track the minimum possible execution time via decreaseTimelock path
persistent ghost mapping(bytes4 => mathint) minDecreaseLock {
    init_state axiom forall bytes4 selector. minDecreaseLock[selector] == max_uint256;
}

// Hook on executableAt writes to track decreaseTimelock submissions
hook Sstore executableAt[KEY bytes hookData] uint256 newValue (uint256 oldValue) {
    require hookData.length >= 36;
    bytes4 selector = EarliestTime.getSelector(hookData);

    // decreaseTimelock == 0x5c1a1a4f
    if (selector == to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector)) {
        require hookData.length >= 68;
        bytes4 targetSelector;
        uint256 newDuration;
        targetSelector, newDuration = EarliestTime.extractDecreaseTimelockArgs(hookData);

        if (oldValue == 0 && newValue != 0 && minDecreaseLock[targetSelector] > newValue + newDuration) {
            minDecreaseLock[targetSelector] = newValue + newDuration;
        } else if (oldValue != 0 && newValue == 0) {
            // Revoke of decreaseTimelock : can only increase or stay same
            mathint newMinimum;
            require newMinimum >= minDecreaseLock[targetSelector];
            minDecreaseLock[targetSelector] = newMinimum;
        }
    }
}

// Hook on executableAt reads to enforce consistency for decreaseTimelock
hook Sload uint256 value executableAt[KEY bytes hookData] {
    require hookData.length >= 36;
    bytes4 selector = EarliestTime.getSelector(hookData);

    // decreaseTimelock == 0x5c1a1a4f
    if (selector == to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector)) {
        require hookData.length >= 68;
        bytes4 targetSelector;
        uint256 newDuration;
        targetSelector, newDuration = EarliestTime.extractDecreaseTimelockArgs(hookData);

        require value == 0 || to_mathint(value) + newDuration >= minDecreaseLock[targetSelector];
    }
}

function min3(mathint a, mathint b, mathint c) returns mathint {
    mathint minAB = a < b ? a : b;
    return minAB < c ? minAB : c;
}

function earliestExecutionTime(env e, bytes data) returns mathint {
    require data.length >= 36;
    bytes4 selector = EarliestTime.getSelector(data);
    mathint execAtValue = to_mathint(executableAt(data)) == 0 ? max_uint256 : to_mathint(executableAt(data));
    mathint directSubmitTime = require_uint256(e.block.timestamp + timelock(selector));
    mathint viaDecreaseTime = minDecreaseLock[selector];
    return min3(execAtValue,directSubmitTime,viaDecreaseTime);
}

// Similar to guardianUpdateTime from vault v1.
// Earliest execution time is monotonically non-decreasing across three paths:
    // 1. Direct execution via executableAt[data] (if already submitted)
    // 2. Fresh submission at current time with timelock[selector]
    // 3. Execution after a pending decreaseTimelock takes effect
// [BUG] Currently there is a bug on the prover for handling msg.data in the hook that's why decreaseTimelock is filtered
rule earliestExecutionTimeIncreases(env e, env e_next, bytes data, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract && !f.isView && f.selector != sig:decreaseTimelock(bytes4, uint256).selector
}
{
    require e_next.block.timestamp >= e.block.timestamp;
    require executableAt(data) != 0;

    mathint earliestTimeBefore = earliestExecutionTime(e, data);

    f(e_next, args);

    mathint earliestTimeAfter = earliestExecutionTime(e_next, data);

    assert earliestTimeAfter >= earliestTimeBefore;
}

// Function must revert if called before earliest execution time.
rule cannotExecuteBeforeMinimumTime(env e,method fb,method f, calldataarg args)
    filtered {
        fb -> fb.contract == EarliestTime && fb.isFallback,
        f -> functionIsTimelocked(f) && f.selector != sig:decreaseTimelock(bytes4, uint256).selector
    }
{
    bytes4 selector = to_bytes4(f.selector);
    require !abdicated(selector);

    // Check currentTime < min(time1, time2)
    fb(e, args);

    f@withrevert(e, args);
    assert lastReverted, "Function must revert before minimum executable time";
}
