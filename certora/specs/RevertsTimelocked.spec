// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// RevertsTimelocked.spec
//
// This specification verifies the revert conditions for timelocked function EXECUTION.
// Uses the consolidated RevertsTimelocked helper with selector-based filtering.

using RevertsTimelockedHelpers as RevertsTimelockedHelpers;

methods {
    function multicall(bytes[]) external => NONDET DELETE;
}

// ============================================================================
// REVERT CONDITION RULES FOR EACH TIMELOCKED FUNCTION
// ============================================================================
//
// Pattern for each rule:
// 1. Call the helper function with the same calldataarg
// 2. If helper passes (meaning one of the revert conditions is met), call the actual function
// 3. Assert that the function reverted

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


// -- PARAMETRIC -- // 

rule parametricRevertCondition(env e, calldataarg args, method f)
filtered {
    f -> f.contract == currentContract && functionTimelocked(f)
} {    
    // Manually dispatch to the corresponding checker function based on selector
    if (f.selector == sig:setIsAllocator(address, bool).selector) {
        RevertsTimelockedHelpers.setIsAllocator(e, args);
    } else if (f.selector == sig:setReceiveSharesGate(address).selector) {
        RevertsTimelockedHelpers.setReceiveSharesGate(e, args);
    } else if (f.selector == sig:setSendSharesGate(address).selector) {
        RevertsTimelockedHelpers.setSendSharesGate(e, args);
    } else if (f.selector == sig:setReceiveAssetsGate(address).selector) {
        RevertsTimelockedHelpers.setReceiveAssetsGate(e, args);
    } else if (f.selector == sig:setSendAssetsGate(address).selector) {
        RevertsTimelockedHelpers.setSendAssetsGate(e, args);
    } else if (f.selector == sig:setAdapterRegistry(address).selector) {
        RevertsTimelockedHelpers.setAdapterRegistry(e, args);
    } else if (f.selector == sig:addAdapter(address).selector) {
        RevertsTimelockedHelpers.addAdapter(e, args);
    } else if (f.selector == sig:removeAdapter(address).selector) {
        RevertsTimelockedHelpers.removeAdapter(e, args);
    } else if (f.selector == sig:increaseTimelock(bytes4, uint256).selector) {
        RevertsTimelockedHelpers.increaseTimelock(e, args);
    } else if (f.selector == sig:decreaseTimelock(bytes4, uint256).selector) {
        RevertsTimelockedHelpers.decreaseTimelock(e, args);
    } else if (f.selector == sig:abdicate(bytes4).selector) {
        RevertsTimelockedHelpers.abdicate(e, args);
    } else if (f.selector == sig:setPerformanceFee(uint256).selector) {
        RevertsTimelockedHelpers.setPerformanceFee(e, args);
    } else if (f.selector == sig:setManagementFee(uint256).selector) {
        RevertsTimelockedHelpers.setManagementFee(e, args);
    } else if (f.selector == sig:setPerformanceFeeRecipient(address).selector) {
        RevertsTimelockedHelpers.setPerformanceFeeRecipient(e, args);
    } else if (f.selector == sig:setManagementFeeRecipient(address).selector) {
        RevertsTimelockedHelpers.setManagementFeeRecipient(e, args);
    } else if (f.selector == sig:increaseAbsoluteCap(bytes,uint256).selector) {
        RevertsTimelockedHelpers.increaseAbsoluteCap(e, args);
    } else if (f.selector == sig:increaseRelativeCap(bytes,uint256).selector) {
        RevertsTimelockedHelpers.increaseRelativeCap(e, args);
    } else if (f.selector == sig:setForceDeallocatePenalty(address,uint256).selector) {
        RevertsTimelockedHelpers.setForceDeallocatePenalty(e, args);
    } else {
        assert false, "Unexpected selector";
    }
    
    f@withrevert(e, args);
    assert lastReverted, "When checker passes, morpho should revert";
}


// -- PER FUNCTION -- // 


// setIsAllocator(address account, bool newIsAllocator)
rule setIsAllocatorRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setIsAllocator(e, args); 
    
    setIsAllocator@withrevert(e, args);
    assert lastReverted, "setIsAllocator should revert when conditions are met";
}

// setReceiveSharesGate(address newReceiveSharesGate)
rule setReceiveSharesGateRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setReceiveSharesGate(e, args);
    
    setReceiveSharesGate@withrevert(e, args);
    assert lastReverted, "setReceiveSharesGate should revert when conditions are met";
}

// setSendSharesGate(address newSendSharesGate)
rule setSendSharesGateRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setSendSharesGate(e, args);
    
    setSendSharesGate@withrevert(e, args);
    assert lastReverted, "setSendSharesGate should revert when conditions are met";
}

// setReceiveAssetsGate(address newReceiveAssetsGate)
rule setReceiveAssetsGateRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setReceiveAssetsGate(e, args);
    
    setReceiveAssetsGate@withrevert(e, args);
    assert lastReverted, "setReceiveAssetsGate should revert when conditions are met";
}

// setSendAssetsGate(address newSendAssetsGate)
rule setSendAssetsGateRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setSendAssetsGate(e, args);
    
    setSendAssetsGate@withrevert(e, args);
    assert lastReverted, "setSendAssetsGate should revert when conditions are met";
}

// setAdapterRegistry(address newAdapterRegistry)
rule setAdapterRegistryRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setAdapterRegistry(e, args);
    
    setAdapterRegistry@withrevert(e, args);
    assert lastReverted, "setAdapterRegistry should revert when conditions are met";
}

// addAdapter(address account)
rule addAdapterRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.addAdapter(e, args);
    
    addAdapter@withrevert(e, args);
    assert lastReverted, "addAdapter should revert when conditions are met";
}

// removeAdapter(address account)
rule removeAdapterRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.removeAdapter(e, args);
    
    removeAdapter@withrevert(e, args);
    assert lastReverted, "removeAdapter should revert when conditions are met";
}

// increaseTimelock(bytes4 targetSelector, uint256 newDuration)
rule increaseTimelockRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.increaseTimelock(e, args);
    
    increaseTimelock@withrevert(e, args);
    assert lastReverted, "increaseTimelock should revert when conditions are met";
}

// decreaseTimelock(bytes4 targetSelector, uint256 newDuration)
rule decreaseTimelockRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.decreaseTimelock(e, args);
    
    decreaseTimelock@withrevert(e, args);
    assert lastReverted, "decreaseTimelock should revert when conditions are met";
}

// abdicate(bytes4 targetSelector)
rule abdicateRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.abdicate(e, args);
    
    abdicate@withrevert(e, args);
    assert lastReverted, "abdicate should revert when conditions are met";
}

// setPerformanceFee(uint256 newPerformanceFee)
rule setPerformanceFeeRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setPerformanceFee(e, args);
    
    setPerformanceFee@withrevert(e, args);
    assert lastReverted, "setPerformanceFee should revert when conditions are met";
}

// setManagementFee(uint256 newManagementFee)
rule setManagementFeeRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setManagementFee(e, args);
    
    setManagementFee@withrevert(e, args);
    assert lastReverted, "setManagementFee should revert when conditions are met";
}

// setPerformanceFeeRecipient(address newPerformanceFeeRecipient)
rule setPerformanceFeeRecipientRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setPerformanceFeeRecipient(e, args);
    
    setPerformanceFeeRecipient@withrevert(e, args);
    assert lastReverted, "setPerformanceFeeRecipient should revert when conditions are met";
}

// setManagementFeeRecipient(address newManagementFeeRecipient)
rule setManagementFeeRecipientRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setManagementFeeRecipient(e, args);
    
    setManagementFeeRecipient@withrevert(e, args);
    assert lastReverted, "setManagementFeeRecipient should revert when conditions are met";
}

// increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap)
rule increaseAbsoluteCapRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.increaseAbsoluteCap(e, args);
    
    increaseAbsoluteCap@withrevert(e, args);
    assert lastReverted, "increaseAbsoluteCap should revert when conditions are met";
}

// increaseRelativeCap(bytes memory idData, uint256 newRelativeCap)
rule increaseRelativeCapRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.increaseRelativeCap(e, args);
    
    increaseRelativeCap@withrevert(e, args);
    assert lastReverted, "increaseRelativeCap should revert when conditions are met";
}

// setForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty)
rule setForceDeallocatePenaltyRevertCondition(env e, calldataarg args) 
{
    RevertsTimelockedHelpers.setForceDeallocatePenalty(e, args);
    
    setForceDeallocatePenalty@withrevert(e, args);
    assert lastReverted, "setForceDeallocatePenalty should revert when conditions are met";
}
