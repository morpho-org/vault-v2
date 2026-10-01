// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using EarliestTime as EarliestTime;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function EarliestTime.timelockSelector(bytes) external returns (bytes4) envfree;
    function EarliestTime.hash(bytes) external returns (bytes32) envfree;
    function EarliestTime.decreaseTimelockArgs(bytes) external returns (bool, bytes4, uint256) envfree;
}

// Mirror of executableAt restricted to data executable as decreaseTimelock(selector, newDuration).
// Keyed by the hash of the data as well because different data can encode the same call (e.g. with trailing bytes).
// Hooks do not reliably decode the data, so instead of being tracked with hooks, this ghost is tied to the storage in the rules at the data that the called function reads and writes.
persistent ghost mapping(bytes4 => mapping(uint256 => mapping(bytes32 => uint256))) decreaseTimelockExecutableAt;

// Value of the last executableAt read, which is the one at the calldata of a timelocked function when it is called.
persistent ghost uint256 lastLoadedExecutableAt;

hook Sload uint256 value executableAt[KEY bytes data] {
    lastLoadedExecutableAt = value;
}

// Key and value of the last timelock write, which are the arguments of decreaseTimelock when it is called.
persistent ghost bytes4 lastTimelockSelector;

persistent ghost uint256 lastTimelockDuration;

hook Sstore timelock[KEY bytes4 selector] uint256 duration {
    lastTimelockSelector = selector;
    lastTimelockDuration = duration;
}

function min(mathint a, mathint b, mathint c) returns mathint {
    mathint minAB = a < b ? a : b;
    return minAB < c ? minAB : c;
}

// Minimum of executableAt[data] + newDuration over the pending data executable as decreaseTimelock(selector, newDuration).
// Returns max_uint256 when there is no such data.
function minViaDecreaseTimelock(bytes4 selector) returns mathint {
    mathint minTime;
    require forall uint256 newDuration. forall bytes32 dataHash. decreaseTimelockExecutableAt[selector][newDuration][dataHash] == 0 || minTime <= decreaseTimelockExecutableAt[selector][newDuration][dataHash] + newDuration, "minTime is a lower bound";
    require minTime == max_uint256 || (exists uint256 newDuration. exists bytes32 dataHash. decreaseTimelockExecutableAt[selector][newDuration][dataHash] != 0 && minTime == decreaseTimelockExecutableAt[selector][newDuration][dataHash] + newDuration), "minTime is reached";
    return minTime;
}

// Earliest time at which some data can be executed, where timelockSelector is the selector whose timelock applies to it (see VaultV2.submit), timelockDuration this timelock and executableAt its current executableAt.
function earliestExecutionTime(uint256 blockTimestamp, bytes4 timelockSelector, uint256 timelockDuration, uint256 executableAt) returns mathint {
    mathint viaDirectExecution = to_mathint(executableAt) == 0 ? max_uint256 : to_mathint(executableAt);
    mathint viaFreshSubmission = require_uint256(blockTimestamp + timelockDuration);
    mathint viaDecreaseTimelock = minViaDecreaseTimelock(timelockSelector);

    return min(viaDirectExecution, viaFreshSubmission, viaDecreaseTimelock);
}

definition takesData(method f) returns bool = f.selector == sig:submit(bytes).selector || f.selector == sig:revoke(bytes).selector;

// Similar to guardianUpdateTime from vault v1.
// Earliest execution time is monotonically non-decreasing across three paths:
// 1. Direct execution via executableAt[data] (if already submitted)
// 2. Fresh submission at current time with the timelock that applies to data
// 3. Execution after any pending decreaseTimelock of that timelock takes effect
// The fallback of EarliestTime, called with the calldata of f, records what f reads and writes in executableAt.
rule earliestExecutionTimeIncreases(env e, method f, calldataarg args, method fb)
filtered {
    fb -> fb.contract == EarliestTime && fb.isFallback,
    f -> f.contract == currentContract
} {
    bytes data;
    bytes4 timelockSelector = EarliestTime.timelockSelector(data);
    uint256 blockTimestampBefore;
    require blockTimestampBefore <= e.block.timestamp, "timestamps are not decreasing";

    // The data that f reads and writes in executableAt: the argument of submit and revoke (data itself or another data), the calldata of f otherwise.
    bytes argument;
    bool argumentIsData;
    bytes submitted;
    if (argumentIsData) {
        submitted = data;
    } else {
        require EarliestTime.hash(argument) != EarliestTime.hash(data), "argument is another data";
        submitted = argument;
    }

    // Its hash and executableAt before the call.
    bytes32 dataHash;
    uint256 executableAtBefore;
    if (takesData(f)) {
        dataHash = EarliestTime.hash(submitted);
        executableAtBefore = executableAt(submitted);
    } else {
        fb(e, args);
        dataHash = EarliestTime.lastHash;
        executableAtBefore = EarliestTime.lastExecutableAt;
    }

    mathint earliestTimeBefore = earliestExecutionTime(blockTimestampBefore, timelockSelector, timelock(timelockSelector), executableAt(data));

    if (f.selector == sig:submit(bytes).selector) {
        submit(e, submitted);
    } else if (f.selector == sig:revoke(bytes).selector) {
        revoke(e, submitted);
    } else {
        f(e, args);
    }

    // Whether that data is executable as decreaseTimelock(decreasedSelector, newDuration), decoded from the argument or taken from the write of decreaseTimelock to timelock, and its executableAt after the call.
    bool isDecreaseTimelock;
    bytes4 decreasedSelector;
    uint256 newDuration;
    uint256 executableAtAfter;
    if (takesData(f)) {
        isDecreaseTimelock, decreasedSelector, newDuration = EarliestTime.decreaseTimelockArgs(submitted);
        executableAtAfter = executableAt(submitted);
    } else {
        isDecreaseTimelock = f.selector == sig:decreaseTimelock(bytes4, uint256).selector;
        decreasedSelector = lastTimelockSelector;
        newDuration = lastTimelockDuration;
        fb(e, args);
        executableAtAfter = EarliestTime.lastExecutableAt;
    }

    // Tie the ghost (which the call does not modify) to the storage before the call at that data, then update it with the storage after the call.
    require !isDecreaseTimelock || decreaseTimelockExecutableAt[decreasedSelector][newDuration][dataHash] == executableAtBefore, "the ghost mirrors the storage";
    if (isDecreaseTimelock) {
        decreaseTimelockExecutableAt[decreasedSelector][newDuration][dataHash] = executableAtAfter;
    }

    mathint earliestTimeAfter = earliestExecutionTime(e.block.timestamp, timelockSelector, timelock(timelockSelector), executableAt(data));

    assert earliestTimeAfter >= earliestTimeBefore;
}

// Function must revert if called before earliest execution time.
// Timelocked functions first read executableAt at their calldata, which is recorded by the hook, so the earliest execution time is computed after the call from the state before the call.
rule cannotExecuteBeforeMinimumTime(env e, method f, calldataarg args) filtered { f -> functionIsTimelocked(f) } {
    uint256 blockTimestampBefore;
    require blockTimestampBefore <= e.block.timestamp, "timestamps are not decreasing";

    // The timelock that applies to the calldata of f is the one of its first argument for decreaseTimelock, the one of its selector otherwise.
    bytes4 timelockSelector;
    uint256 timelockBefore;
    if (f.selector == sig:decreaseTimelock(bytes4, uint256).selector) {
        uint256 newDuration;
        timelockBefore = timelock(timelockSelector);
        decreaseTimelock@withrevert(e, timelockSelector, newDuration);
    } else {
        require timelockSelector == to_bytes4(f.selector), "the timelock of f applies";
        timelockBefore = timelock(timelockSelector);
        f@withrevert(e, args);
    }
    bool reverted = lastReverted;

    mathint earliestTime = earliestExecutionTime(blockTimestampBefore, timelockSelector, timelockBefore, lastLoadedExecutableAt);

    require e.block.timestamp < earliestTime, "assume the call happens before the earliest execution time";
    assert reverted;
}
