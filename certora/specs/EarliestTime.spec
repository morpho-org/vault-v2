// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using EarliestTime as EarliestTime;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function EarliestTime.getSelector(bytes) external returns (bytes4) envfree;
    function EarliestTime.extractDecreaseTimelockArgs(bytes) external returns (bytes4, uint256) envfree;
}

// Ghost to track the minimum possible execution time via decreaseTimelock path
persistent ghost mapping(bytes4 => mathint) minDecreaseTimelock {
    init_state axiom forall bytes4 selector. minDecreaseTimelock[selector] == max_uint256;
}

// Hook on executableAt writes to track decreaseTimelock submissions
hook Sstore executableAt[KEY bytes hookData] uint256 newValue (uint256 oldValue) {
    require hookData.length >= 36;
    bytes4 selector = EarliestTime.getSelector(hookData);

    if (selector == to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector)) {
        require hookData.length >= 68;
        bytes4 targetSelector;
        uint256 newDuration;
        targetSelector, newDuration = EarliestTime.extractDecreaseTimelockArgs(hookData);

        if (oldValue == 0 && newValue != 0 && minDecreaseTimelock[targetSelector] > newValue + newDuration) {
            minDecreaseTimelock[targetSelector] = newValue + newDuration;
        } else if (oldValue != 0 && newValue == 0) {
            // Revoke of decreaseTimelock: can only increase or stay same
            mathint newMinimum;
            require newMinimum >= minDecreaseTimelock[targetSelector];
            minDecreaseTimelock[targetSelector] = newMinimum;
        }
    }
}

function min(mathint a, mathint b, mathint c) returns mathint {
    mathint minAB = a < b ? a : b;
    return minAB < c ? minAB : c;
}

// Only call this function with fb the fallback method of the EarliestTime contract.
function earliestExecutionTime(env e, method fb, calldataarg args) returns mathint {
    fb(e, args);
    bytes4 selector = EarliestTime.lastSelector;
    uint256 executableAt = EarliestTime.lastExecutableAt;

    mathint viaDirectExecution = to_mathint(executableAt) == 0 ? max_uint256 : to_mathint(executableAt);
    mathint viaFreshSubmission = require_uint256(e.block.timestamp + timelock(selector));
    mathint viaDecreaseTimelock = minDecreaseTimelock[selector];

    return min(viaDirectExecution, viaFreshSubmission, viaDecreaseTimelock);
}

// Similar to guardianUpdateTime from vault v1.
// Earliest execution time is monotonically non-decreasing across three paths:
// 1. Direct execution via executableAt[data] (if already submitted)
// 2. Fresh submission at current time with timelock[selector]
// 3. Execution after a pending decreaseTimelock takes effect
// [BUG] Currently there is a bug on the prover for handling msg.data in the hook that's why decreaseTimelock is filtered
rule earliestExecutionTimeIncreases(env e, env e_next, method f, calldataarg args, method fb)
filtered {
    fb -> fb.contract == EarliestTime && fb.isFallback,
    f -> f.contract == currentContract && !f.isView && f.selector != sig:decreaseTimelock(bytes4, uint256).selector }
{
    require e_next.block.timestamp >= e.block.timestamp;

    mathint earliestTimeBefore = earliestExecutionTime(e, fb, args);

    f(e_next, args);

    mathint earliestTimeAfter = earliestExecutionTime(e_next, fb, args);

    assert earliestTimeAfter >= earliestTimeBefore;
}

// Function must revert if called before earliest execution time.
rule cannotExecuteBeforeMinimumTime(env e, method f, calldataarg args, method fb)
filtered {
    fb -> fb.contract == EarliestTime && fb.isFallback,
    f -> functionIsTimelocked(f) && f.selector != sig:decreaseTimelock(bytes4, uint256).selector }
{
    mathint earliestTime = earliestExecutionTime(e, fb, args);

    require e.block.timestamp < earliestTime;
    f@withrevert(e, args);
    assert lastReverted;
}
