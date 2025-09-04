// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function timelock(bytes4) external returns uint256 envfree;
    function pendingCount(bytes4) external returns uint256 envfree;
    function executableAt(bytes) external returns uint256 envfree;

    function Utils.toBytes4(bytes) external returns bytes4 envfree;
}

rule timelockMaxFunctionsCantBeSubmitted(env e, method f, calldataarg args, bytes data) {
    // Safe require in a non trivial chain.
    require e.block.timestamp > 0;

    bytes4 selector = Utils.toBytes4(data);
    // Assume that the function has been abdicated.
    require selector != to_bytes4(sig:VaultV2.decreaseTimelock(bytes4, uint256).selector);
    require timelock(selector) == max_uint256;

    uint256 executableAtBefore = executableAt(data);
    uint256 pendingCountBefore = pendingCount(selector);

    f(e, args);

    assert pendingCount(selector) <= pendingCountBefore;
    assert executableAt(data) == 0 || executableAt(data) == executableAtBefore;
}

rule noPendingCountCantBeSet(env e, method f, calldataarg args, bytes data) 
filtered {
    f -> f.selector == sig:setIsAllocator(address,bool).selector
        || f.selector == sig:addAdapter(address).selector
        || f.selector == sig:removeAdapter(address).selector
        || f.selector == sig:setReceiveSharesGate(address).selector
        || f.selector == sig:setSendSharesGate(address).selector
        || f.selector == sig:setReceiveAssetsGate(address).selector
        || f.selector == sig:setSendAssetsGate(address).selector
        || f.selector == sig:increaseAbsoluteCap(bytes,uint256).selector
        || f.selector == sig:increaseRelativeCap(bytes,uint256).selector
        || f.selector == sig:setPerformanceFee(uint256).selector
        || f.selector == sig:setManagementFee(uint256).selector
        || f.selector == sig:setPerformanceFeeRecipient(address).selector
        || f.selector == sig:setManagementFeeRecipient(address).selector
        || f.selector == sig:setForceDeallocatePenalty(address,uint256).selector
        || f.selector == sig:increaseTimelock(bytes4,uint256).selector
        || f.selector == sig:decreaseTimelock(bytes4,uint256).selector
}
{
    require pendingCount(to_bytes4(f.selector)) == 0;

    f@withrevert(e, args);
    assert lastReverted;
}

// Thus (timelock==max && pendingCount==0) => abdicated (= the function can't be called anymore).
