// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ExecutableAtHelpers as ExecutableAtHelpers;

// Check the revert conditions. Because the helper contract is called first, this specification doesn't catch trivial revert conditions like e.msg.value != 0.

methods {
    // Assume that interest accrual does not revert.
    function VaultV2.accrueInterest() internal => NONDET;
    // Assume that the registry is add-only.
    function _.isInRegistry(address adapter) external => ghostIsInRegistry(adapter) expect bool;
}

ghost ghostIsInRegistry(address) returns bool;

rule setIsAllocatorRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setIsAllocator(e, args);

    setIsAllocator@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setReceiveSharesGateRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setReceiveSharesGate(e, args);

    setReceiveSharesGate@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setSendSharesGateRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setSendSharesGate(e, args);

    setSendSharesGate@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setReceiveAssetsGateRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setReceiveAssetsGate(e, args);

    setReceiveAssetsGate@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setSendAssetsGateRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setSendAssetsGate(e, args);

    setSendAssetsGate@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setAdapterRegistryRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setAdapterRegistry(e, args);

    setAdapterRegistry@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule addAdapterRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.addAdapter(e, args);

    addAdapter@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule removeAdapterRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.removeAdapter(e, args);

    removeAdapter@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule increaseTimelockRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.increaseTimelock(e, args);

    increaseTimelock@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule decreaseTimelockRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.decreaseTimelock(e, args);

    decreaseTimelock@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule abdicatedRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.abdicate(e, args);

    abdicate@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule increaseAbsoluteCapRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.increaseAbsoluteCap(e, args);

    increaseAbsoluteCap@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule increaseRelativeCapRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.increaseRelativeCap(e, args);

    increaseRelativeCap@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setForceDeallocatePenaltyRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setForceDeallocatePenalty(e, args);

    setForceDeallocatePenalty@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setPerformanceFeeRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setPerformanceFee(e, args);

    setPerformanceFee@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setManagementFeeRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setManagementFee(e, args);

    setManagementFee@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setPerformanceFeeRecipientRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setPerformanceFeeRecipient(e, args);

    setPerformanceFeeRecipient@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setManagementFeeRecipientRevertConditions(env e, calldataarg args)
{
    bool revertCondition = ExecutableAtHelpers.setManagementFeeRecipient(e, args);

    setManagementFeeRecipient@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}
