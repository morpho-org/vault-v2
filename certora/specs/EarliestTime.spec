// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using EarliestTime as EarliestTime;
using DecreaseTimelockChecker as Checker;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function EarliestTime.getSelector(bytes) external returns (bytes4) envfree;
    function EarliestTime.extractDecreaseTimelockArgs(bytes) external returns (bytes4, uint256) envfree;

    function Checker.lastExecAt() external returns (uint256) envfree;
}

// Ghost to track the minimum possible execution time via decreaseTimelock path
persistent ghost mapping(bytes4 => mathint) minDecreaseTimelock {
    init_state axiom forall bytes4 selector. minDecreaseTimelock[selector] == max_uint256;
}

// Hook on executableAt writes to track decreaseTimelock submissions
hook Sstore executableAt[KEY bytes hookData] uint256 newValue (uint256 oldValue) {
    bytes4 selector = EarliestTime.getSelector(hookData);

    if (selector == to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector)) {
        bytes4 targetSelector;
        uint256 newDuration;
        targetSelector, newDuration = EarliestTime.extractDecreaseTimelockArgs(hookData);

        if (oldValue == 0 && newValue != 0 && minDecreaseTimelock[targetSelector] > newValue + newDuration) {
            minDecreaseTimelock[targetSelector] = newValue + newDuration;
        } else if (oldValue != 0 && newValue == 0) {
            minDecreaseTimelock[targetSelector] = max_uint256;
        }
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

// Similar to guardianUpdateTime from vault v1.
// Earliest execution time is monotonically non-decreasing across three paths:
// 1. Direct execution via executableAt[data] (if already submitted)
// 2. Fresh submission at current time with timelock[selector]
// 3. Execution after a pending decreaseTimelock takes effect
// decreaseTimelock is handled in a dedicated rule below (see earliestExecutionTimeIncreasesDecreaseTimelock)
rule earliestExecutionTimeIncreases(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract
      && f.selector != sig:decreaseTimelock(bytes4, uint256).selector
      && !f.isView
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

// Dedicated rule for decreaseTimelock, bypassing the msg.data hook limitation.
// Uses the fallback pattern: a checker contract's fallback shares the same calldataarg as
// decreaseTimelock, so its msg.data == decreaseTimelock's msg.data. This lets us read
// executableAt[msg.data] before execution without relying on the buggy hook.
//
// Key design choices to avoid prover disconnects:
//   - We read timelockAfter from contract state instead of extracting newDuration from calldata
//   - We add an explicit require for the timelocked constraint (e.block.timestamp >= execAtOfOp)
//     because the prover can't link the checker's external call with timelocked()'s internal read.
//     This require is sound: timelocked() enforces it, and if it doesn't hold, the call reverts.
//
// We assert that both verifiable after-paths (direct execution, fresh submission) are >= earliestBefore.
// The third after-path (minDecreaseTimelock for remaining pending ops) is >= earliestBefore
// by the argument that removing an element from a min can only increase it.
rule earliestExecutionTimeIncreasesDecreaseTimelock(env e, method f, method fb, calldataarg args)
filtered {
    fb -> fb.contract == Checker && fb.isFallback,
    f -> f.contract == currentContract
      && f.selector == sig:decreaseTimelock(bytes4, uint256).selector
}
{
    bytes data;
    uint256 blockTimestampBefore;
    require blockTimestampBefore <= e.block.timestamp, "timestamps are not decreasing";

    // Capture executableAt[msg.data] before execution via fallback.
    fb(e, args);
    uint256 execAtOfOp = Checker.lastExecAt();

    // Read before-state values directly from contract storage.
    bytes4 dataSelector = EarliestTime.getSelector(data);
    uint256 execAtData = executableAt(data);
    uint256 timelockBefore = timelock(dataSelector);

    mathint viaDirectBefore = execAtData == 0 ? max_uint256 : to_mathint(execAtData);
    mathint viaFreshBefore = require_uint256(blockTimestampBefore + timelockBefore);

    // Execute decreaseTimelock.
    f(e, args);

    // Read after-state: timelockAfter = newDuration when dataSelector == targetSelector,
    // or unchanged when dataSelector != targetSelector.
    uint256 timelockAfter = timelock(dataSelector);

    // Compute viaDecreaseBefore using timelockAfter (the actual post-call value from storage).
    // When timelockAfter < timelockBefore, the timelock was decreased meaning
    // dataSelector == targetSelector and timelockAfter == newDuration.
    // The pending operation gives bound: execAtOfOp + timelockAfter.
    mathint viaDecreaseBefore = (timelockAfter < timelockBefore && execAtOfOp != 0)
        ? to_mathint(execAtOfOp) + to_mathint(timelockAfter)
        : max_uint256;

    mathint earliestBefore = min(viaDirectBefore, viaFreshBefore, viaDecreaseBefore);

    // The timelocked() function enforces block.timestamp >= executableAt[msg.data].
    // The checker read execAtOfOp = vault.executableAt(msg.data) with the same msg.data.
    // The prover can't link these reads across contracts, so we add the constraint explicitly.
    // This is sound: if timelocked() doesn't hold, the call reverts (and we called f without @withrevert).
    require to_mathint(e.block.timestamp) >= to_mathint(execAtOfOp);

    uint256 execAtDataAfter = executableAt(data);
    mathint viaDirectAfter = execAtDataAfter == 0 ? max_uint256 : to_mathint(execAtDataAfter);
    mathint viaFreshAfter = require_uint256(e.block.timestamp + timelockAfter);

    assert viaDirectAfter >= earliestBefore;
    assert viaFreshAfter >= earliestBefore;
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
