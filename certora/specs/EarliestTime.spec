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
// Ghost to track the minimum possible execution time for every possible submission
persistent ghost mapping(bytes4 => mapping(bytes32 => mathint)) decreaseTimelockEET {
    init_state axiom forall bytes4 selector.  forall bytes32 hash. decreaseTimelockEET[selector][hash] == max_uint256;
}

definition minimumIsLowerBound(bytes4 selector) returns bool =
    forall bytes32 hash. minDecreaseTimelock[selector] <= decreaseTimelockEET[selector][hash];

definition minimumIsAchievable(bytes4 selector) returns bool =
    exists bytes32 hash. minDecreaseTimelock[selector] == decreaseTimelockEET[selector][hash];

definition earliestTimeFromValueDuration(uint256 value, uint256 duration) returns mathint =
    value > 0 ? value + duration : max_uint256;

// Hook on executableAt writes to track decreaseTimelock submissions
hook Sstore executableAt[KEY bytes hookData] uint256 newValue (uint256 oldValue) {
    bytes4 selector = EarliestTime.getSelector(hookData);

    if (selector == to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector)) {
        bytes4 targetSelector;
        uint256 newDuration;
        targetSelector, newDuration = EarliestTime.extractDecreaseTimelockArgs(hookData);

        decreaseTimelockEET[targetSelector][keccak256(hookData)] = earliestTimeFromValueDuration(newValue, newDuration);
        bytes32 newMinimumWitness;
        mathint newMinimum = decreaseTimelockEET[targetSelector][newMinimumWitness];
        require forall bytes32 hash. newMinimum <= decreaseTimelockEET[targetSelector][hash], "Witness can be chosen for the minimum.";
        minDecreaseTimelock[targetSelector] = newMinimum;
    }
}

// Hook on executableAt writes to track decreaseTimelock submissions
hook Sload uint256 value executableAt[KEY bytes hookData] {
    bytes4 selector = EarliestTime.getSelector(hookData);

    if (selector == to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector)) {
        bytes4 targetSelector;
        uint256 newDuration;
        targetSelector, newDuration = EarliestTime.extractDecreaseTimelockArgs(hookData);

        requireInvariant minimumCorrectlyTracked(targetSelector);
        require decreaseTimelockEET[targetSelector][keccak256(hookData)] == earliestTimeFromValueDuration(value, newDuration), "ghost mirror";
    }
}

function min(mathint a, mathint b, mathint c) returns mathint {
    mathint minAB = a < b ? a : b;
    return minAB < c ? minAB : c;
}

function earliestExecutionTimeFromData(uint256 blockTimestamp, bytes data) returns mathint {
    bytes4 selector = EarliestTime.getSelector(data);
    uint256 executableAt = executableAt(data);
    return earliestExecutionTime(blockTimestamp, selector, executableAt);
}

function earliestExecutionTime(uint256 blockTimestamp, bytes4 selector, uint256 executableAt) returns mathint {
    mathint viaDirectExecution = to_mathint(executableAt) == 0 ? max_uint256 : to_mathint(executableAt);
    mathint viaFreshSubmission = require_uint256(blockTimestamp + timelock(selector));
    mathint viaDecreaseTimelock = minDecreaseTimelock[selector];

    return min(viaDirectExecution, viaFreshSubmission, viaDecreaseTimelock);
}

invariant minimumCorrectlyTracked(bytes4 selector) 
    minimumIsLowerBound(selector) && minimumIsAchievable(selector)
filtered { f -> f.contract == currentContract }


// Similar to guardianUpdateTime from vault v1.
// Earliest execution time is monotonically non-decreasing across three paths:
// 1. Direct execution via executableAt[data] (if already submitted)
// 2. Fresh submission at current time with timelock[selector]
// 3. Execution after a pending decreaseTimelock takes effect
// [BUG] Currently there is a bug on the prover for handling msg.data in the hook that's why decreaseTimelock is filtered
rule earliestExecutionTimeIncreases(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract && f.selector != sig:decreaseTimelock(bytes4, uint256).selector
}
{
    bytes data;
    uint256 blockTimestampBefore;
    require blockTimestampBefore <= e.block.timestamp, "timestamps are not decreasing";

    mathint earliestTimeBefore = earliestExecutionTimeFromData(blockTimestampBefore, data);

    f(e, args);

    mathint earliestTimeAfter = earliestExecutionTimeFromData(e.block.timestamp, data);

    assert earliestTimeAfter >= earliestTimeBefore;
}

// Function must revert if called before earliest execution time.
rule cannotExecuteBeforeMinimumTime(env e, method f, calldataarg args, method fb)
filtered {
    fb -> fb.contract == EarliestTime && fb.isFallback,
    f -> functionIsTimelocked(f) && f.selector != sig:decreaseTimelock(bytes4, uint256).selector }
{
    uint256 blockTimestampBefore;
    require blockTimestampBefore <= e.block.timestamp, "timestamps are not decreasing";

    // Retrieve the last selector and executableAt from the fallback call.
    fb(e, args);
    bytes4 selector = EarliestTime.lastSelector;
    uint256 executableAt = EarliestTime.lastExecutableAt;

    mathint earliestTime = earliestExecutionTime(blockTimestampBefore, selector, executableAt);

    require e.block.timestamp < earliestTime, "assume the call happens before the earliest execution time";
    f@withrevert(e, args);
    assert lastReverted;
}
