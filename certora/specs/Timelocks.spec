// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using TimelockManagerHelpers as TimelockManagerHelpers;
using BeforeMinimumTimeChecker as BeforeMinimumTimeChecker;
using NotSubmittedHarness as NotSubmittedHarness;
using RevokeHarness as RevokeHarness;


methods {

    function multicall(bytes[]) external => NONDET DELETE;

    // Vault getters
    function curator() external returns address envfree;
    function timelock(bytes4) external returns uint256 envfree;
    function executableAt(bytes) external returns uint256 envfree;
    function abdicated(bytes4) external returns bool envfree;
    
    // Harness functions
    function TimelockManagerHelpers.getSelector(bytes) external returns bytes4 envfree;
    function TimelockManagerHelpers.isDecreaseTimelock(bytes) external returns bool envfree;
    function TimelockManagerHelpers.extractDecreaseTimelockArgs(bytes) external returns (bytes4, uint256) envfree;
}

// Ghost to track the minimum possible execution time via decreaseTimelock path
persistent ghost mapping(bytes4 => mathint) minDecreaseLock {
    init_state axiom forall bytes4 selector. minDecreaseLock[selector] == max_uint256;
}

// Hook on executableAt writes to track decreaseTimelock submissions
hook Sstore executableAt[KEY bytes hookData] uint256 newValue (uint256 oldValue) {
    require hookData.length >= 36;
    bytes4 selector = TimelockManagerHelpers.getSelector(hookData);
    
    // decreaseTimelock == 0x5c1a1a4f
    if (selector == to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector)) {
        require hookData.length >= 68;
        bytes4 targetSelector;
        uint256 newDuration;
        targetSelector, newDuration = TimelockManagerHelpers.extractDecreaseTimelockArgs(hookData);
        
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
    bytes4 selector = TimelockManagerHelpers.getSelector(hookData);
    
    // decreaseTimelock == 0x5c1a1a4f
    if (selector == to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector)) {
        require hookData.length >= 68;
        bytes4 targetSelector;
        uint256 newDuration;
        targetSelector, newDuration = TimelockManagerHelpers.extractDecreaseTimelockArgs(hookData);
        
        require value == 0 || to_mathint(value) + newDuration >= minDecreaseLock[targetSelector];
    }
}

definition functionTimelocked(method f) returns bool = 
    f.selector == sig:setIsAllocator(address, bool).selector ||
    f.selector == sig:setReceiveSharesGate(address).selector ||
    f.selector == sig:setSendSharesGate(address).selector ||
    f.selector == sig:setReceiveAssetsGate(address).selector ||
    f.selector == sig:setSendAssetsGate(address).selector ||
    f.selector == sig:setAdapterRegistry(address).selector ||
    f.selector == sig:addAdapter(address).selector ||
    f.selector == sig:removeAdapter(address).selector ||
    f.selector == sig:increaseTimelock(bytes4, uint256).selector ||
    f.selector == sig:decreaseTimelock(bytes4, uint256).selector ||
    f.selector == sig:abdicate(bytes4).selector ||
    f.selector == sig:setPerformanceFee(uint256).selector ||
    f.selector == sig:setManagementFee(uint256).selector ||
    f.selector == sig:setPerformanceFeeRecipient(address).selector ||
    f.selector == sig:setManagementFeeRecipient(address).selector ||
    f.selector == sig:increaseAbsoluteCap(bytes,uint256).selector ||
    f.selector == sig:increaseRelativeCap(bytes,uint256).selector ||
    f.selector == sig:setForceDeallocatePenalty(address,uint256).selector;


function extractExpectedDelay(bytes data) returns uint256 {
    bytes4 selector = TimelockManagerHelpers.getSelector(data);
    if (TimelockManagerHelpers.isDecreaseTimelock(data)) {
        bytes4 targetSelector;
        uint256 newTimelock;
        targetSelector, newTimelock = TimelockManagerHelpers.extractDecreaseTimelockArgs(data);
        return timelock(targetSelector);
    } else {
        return timelock(selector);
    }
}

function min3(mathint a, mathint b, mathint c) returns mathint {
    mathint minAB = a < b ? a : b;
    return minAB < c ? minAB : c;
}

// Similar to guardianUpdateTime from MetaMorpho
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
    require data.length >= 36;
    bytes4 selector = TimelockManagerHelpers.getSelector(data);
    
    // Compute earliest execution time BEFORE interaction
    mathint execAtValue = to_mathint(executableAt(data)) == 0 ? max_uint256 : to_mathint(executableAt(data));
    mathint directSubmitTime = require_uint256(e.block.timestamp + timelock(selector));
    mathint viaDecreaseTime = minDecreaseLock[selector];
    mathint earliestBefore = min3(execAtValue,directSubmitTime,viaDecreaseTime);
    
    // Arbitrary function call (any state change)
    f(e_next, args);
    
    // Compute earliest execution time AFTER interaction
    mathint execAtValueAfter = to_mathint(executableAt(data)) == 0 ? max_uint256 : to_mathint(executableAt(data));
    mathint directSubmitTimeAfter = require_uint256(e_next.block.timestamp + timelock(selector));
    mathint viaDecreaseTimeAfter = minDecreaseLock[selector];
    mathint earliestAfter = min3(execAtValueAfter ,directSubmitTimeAfter,viaDecreaseTimeAfter);
    
    assert earliestAfter >= earliestBefore;
}

// Submit correctly sets executableAt based on timelock
rule submitSetsCorrectExecutableAt(env e, bytes data) {
    bytes4 selector = TimelockManagerHelpers.getSelector(data);
    
    require e.msg.sender == curator();
    require executableAt(data) == 0;
    
    uint256 expectedDelay = extractExpectedDelay(data);
    
    uint256 timeBefore = e.block.timestamp;
    submit(e, data);
    
    assert executableAt(data) == assert_uint256(timeBefore + expectedDelay), "executableAt must equal timestamp + appropriate timelock";
}


// Function must revert if called before submission
rule cannotExecuteBeforeMinimumTime(env e,method fb,method f, calldataarg args) 
    filtered { 
        fb -> fb.contract == BeforeMinimumTimeChecker && fb.isFallback,
        f -> functionTimelocked(f) && f.selector != sig:decreaseTimelock(bytes4, uint256).selector
    }
{
    bytes4 selector = to_bytes4(f.selector);
    require !abdicated(selector);
    
    // The fallback will check msg.data and verify we're BEFORE minimum time
    // If it doesn't revert, we know: currentTime < min(time1, time2)
    fb(e, args);
    
    // Now call the actual function with the SAME calldataarg (same msg.data)
        // => MUST revert since we're before the minimum time
    f@withrevert(e, args);
    assert lastReverted, "Function must revert before minimum executable time";
}

// Abdicated functions cannot be called
rule abdicatedFunctionsMustRevert(env e, method f, calldataarg args)
filtered { 
    f -> functionTimelocked(f)
}
{
    bytes4 selector = to_bytes4(f.selector);
    require abdicated(selector);
    
    f@withrevert(e, args);
    assert lastReverted, "Abdicated functions must always revert";
}

// Function must revert if not submitted for execution
rule mustRevertIfNotSubmitted(env e, method fb, method f, calldataarg args)
    filtered {
        fb -> fb.contract == NotSubmittedHarness && fb.isFallback,
        f -> functionTimelocked(f)
    }
{
    bytes4 selector = to_bytes4(f.selector);
    require !abdicated(selector);
    
    // Fallback will check executableAt[msg.data] == 0
    fb(e, args);

    // If fallback reverted due to "Data not submitted", function should also revert
    f@withrevert(e, args);
    assert lastReverted, "Function must revert if data not submitted";
}

// Function must revert if revoked
rule revokePreventsFutureExecution(env e, method revokeFb, method f, calldataarg args)
    filtered { 
        revokeFb -> revokeFb.contract == RevokeHarness && revokeFb.isFallback,
        f -> functionTimelocked(f)
    }
{    

    // Revoke using the RevokeHarness fallback 
    revokeFb(e, args);
    
    // Verify that trying to call the function now fails
    f@withrevert(e, args);
    assert lastReverted, "Revoked data should revert";
}