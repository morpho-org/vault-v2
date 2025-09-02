// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function timelock(bytes4 selector) external returns uint256 envfree;

    function Utils.toBytes4(bytes) external returns bytes4 envfree;
    function Utils.toBytes4(uint32) external returns bytes4 envfree;
}

// Check that it is possible to set a function's timelock to uint max.
rule abdicatedFunctionHasInfiniteTimelock(env e, bytes4 selector) {
    increaseTimelock(e, selector, max_uint256);

    assert timelock(selector) == max_uint256;
}

// Check that changes corresponding to functions that have been abdicated can't be submitted.
rule abdicatedFunctionsCantBeSubmitted(env e, bytes data) {
    // Safe require in a non trivial chain.
    require e.block.timestamp > 0;

    // Check that the function is not decreaseTimelock as its timelock is automatic.
    require(Utils.toBytes4(data) != to_bytes4(sig:VaultV2.decreaseTimelock(bytes4, uint256).selector));
    // Assume that the function has been abdicated.
    require timelock(Utils.toBytes4(data)) == max_uint256;

    submit@withrevert(e, data);
    assert lastReverted;
}

// Check that timelocked functions with timelock=max can't be set, even with previously submitted data.
rule abdicatedFunctionsCantBeSet(env e, method f, calldataarg args) 
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
    require timelock(Utils.toBytes4(f.selector)) == max_uint256;

    f@withrevert(e, args);
    assert lastReverted;
} 
