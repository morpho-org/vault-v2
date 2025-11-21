// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association


// ExecutableAtHelpers.spec
// This specification verifies that each individual timelocked function can be 
// successfully executed after the timelock period expires.
//  Each rule:
    // 1. Uses the consolidated ExecutableAt helper that checks both timelock 
    //    conditions and function-specific business logic constraints
    // 2. Verifies the function can execute when all conditions are met

using ExecutableAtHelpers as ExecutableAtHelpers;

methods {
    function VaultV2.accrueInterestView() internal returns (uint256, uint256, uint256) => accrueInterestViewSummary();
    function _.isInRegistry(address) external => ALWAYS(true);
}

function accrueInterestViewSummary() returns (uint256, uint256, uint256) {
    return (currentContract._totalAssets, 0, 0);
}

// ============================================================================
// PER-FUNCTION RULES - WORKING SCENARIO
// ============================================================================

rule canExecuteSetIsAllocator(env e, calldataarg args) 
{
    ExecutableAtHelpers.setIsAllocator(e, args);

    setIsAllocator@withrevert(e, args);
    assert !lastReverted, "setIsAllocator should succeed after helper checks pass";
}

rule canExecuteSetReceiveSharesGate(env e, calldataarg args) 
{
    ExecutableAtHelpers.setReceiveSharesGate(e, args);
    
    setReceiveSharesGate@withrevert(e, args);
    assert !lastReverted, "setReceiveSharesGate should succeed after helper checks pass";
}

rule canExecuteSetSendSharesGate(env e, calldataarg args) 
{
    ExecutableAtHelpers.setSendSharesGate(e, args);

    setSendSharesGate@withrevert(e, args);
    assert !lastReverted, "setSendSharesGate should succeed after helper checks pass";
}

rule canExecuteSetReceiveAssetsGate(env e, calldataarg args) 
{
    ExecutableAtHelpers.setReceiveAssetsGate(e, args);
    
    setReceiveAssetsGate@withrevert(e, args);
    assert !lastReverted, "setReceiveAssetsGate should succeed after helper checks pass";
}

rule canExecuteSetSendAssetsGate(env e, calldataarg args) 
{
    ExecutableAtHelpers.setSendAssetsGate(e, args);
    
    setSendAssetsGate@withrevert(e, args);
    assert !lastReverted, "setSendAssetsGate should succeed after helper checks pass";
}

rule canExecuteSetAdapterRegistry(env e, calldataarg args) 
{
    ExecutableAtHelpers.setAdapterRegistry(e, args);
    
    setAdapterRegistry@withrevert(e, args);
    assert !lastReverted, "setAdapterRegistry should succeed after helper checks pass";
}

rule canExecuteAddAdapter(env e, calldataarg args) 
{
    ExecutableAtHelpers.addAdapter(e, args);
    
    addAdapter@withrevert(e, args);
    assert !lastReverted;
}

rule canExecuteRemoveAdapter(env e, calldataarg args) 
{
    ExecutableAtHelpers.removeAdapter(e, args);
    
    removeAdapter@withrevert(e, args);
    assert !lastReverted, "removeAdapter should succeed after helper checks pass";
}

rule canExecuteIncreaseTimelock(env e, calldataarg args) 
{
    ExecutableAtHelpers.increaseTimelock(e, args);
    
    increaseTimelock@withrevert(e, args);
    assert !lastReverted, "increaseTimelock should succeed after helper checks pass";
}

rule canExecuteDecreaseTimelock(env e, calldataarg args) 
{
    ExecutableAtHelpers.decreaseTimelock(e, args);
    
    decreaseTimelock@withrevert(e, args);
    assert !lastReverted, "decreaseTimelock should succeed after helper checks pass";
}

rule canExecuteAbdicate(env e, calldataarg args) 
{
    ExecutableAtHelpers.abdicate(e, args);
    
    abdicate@withrevert(e, args);
    assert !lastReverted, "abdicate should succeed after helper checks pass";
}

rule canExecuteIncreaseAbsoluteCap(env e, calldataarg args) 
{
    ExecutableAtHelpers.increaseAbsoluteCap(e, args);
    
    increaseAbsoluteCap@withrevert(e, args);
    assert !lastReverted;
}

rule canExecuteIncreaseRelativeCap(env e, calldataarg args) 
{
    ExecutableAtHelpers.increaseRelativeCap(e, args);
    
    increaseRelativeCap@withrevert(e, args);
    assert !lastReverted;
}

rule canExecuteSetForceDeallocatePenalty(env e, calldataarg args) 
{
    ExecutableAtHelpers.setForceDeallocatePenalty(e, args);
    
    setForceDeallocatePenalty@withrevert(e, args);
    assert !lastReverted, "setForceDeallocatePenalty should succeed after helper checks pass";
}

rule canExecuteSetPerformanceFee(env e, calldataarg args) 
{
    ExecutableAtHelpers.setPerformanceFee(e, args);
    
    setPerformanceFee@withrevert(e, args);
    assert !lastReverted, "setPerformanceFee should succeed after helper checks pass";
}

rule canExecuteSetManagementFee(env e, calldataarg args) 
{
    ExecutableAtHelpers.setManagementFee(e, args);
    
    setManagementFee@withrevert(e, args);
    assert !lastReverted, "setManagementFee should succeed after helper checks pass";
}

rule canExecuteSetPerformanceFeeRecipient(env e, calldataarg args) 
{
    ExecutableAtHelpers.setPerformanceFeeRecipient(e, args);
    
    setPerformanceFeeRecipient@withrevert(e, args);
    assert !lastReverted, "setPerformanceFeeRecipient should succeed after helper checks pass";
}

rule canExecuteSetManagementFeeRecipient(env e, calldataarg args) 
{
    ExecutableAtHelpers.setManagementFeeRecipient(e, args);
    
    setManagementFeeRecipient@withrevert(e, args);
    assert !lastReverted, "setManagementFeeRecipient should succeed after helper checks pass";
}

