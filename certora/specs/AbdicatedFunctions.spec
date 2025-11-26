// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => NONDET DELETE;
    function abdicated(bytes4) external returns (bool) envfree;

    function receiveSharesGate() external returns (address) envfree;
    function sendSharesGate() external returns (address) envfree;
    function receiveAssetsGate() external returns (address) envfree;
    function sendAssetsGate() external returns (address) envfree;
    function adapterRegistry() external returns (address) envfree;
    function isSentinel(address account) external returns (bool) envfree;
    function isAllocator(address account) external returns (bool) envfree;
    function adapters(uint256 index) external returns (address) envfree;
    function isAdapter(address account) external returns (bool) envfree;
    function absoluteCap(bytes32 id) external returns (uint256) envfree;
    function relativeCap(bytes32 id) external returns (uint256) envfree;
    function forceDeallocatePenalty(address adapter) external returns (uint256) envfree;
    function timelock(bytes4 selector) external returns (uint256) envfree;
    function abdicated(bytes4 selector) external returns (bool) envfree;
    function performanceFee() external returns (uint96) envfree;
    function performanceFeeRecipient() external returns (address) envfree;
    function managementFee() external returns (uint96) envfree;
    function managementFeeRecipient() external returns (address) envfree;
}

rule abdicatedFunctionsCantBeCalled(env e, method f, calldataarg args)
filtered {
    f -> f.selector == sig:setIsAllocator(address,bool).selector
        || f.selector == sig:addAdapter(address).selector
        || f.selector == sig:removeAdapter(address).selector
        || f.selector == sig:setReceiveSharesGate(address).selector
        || f.selector == sig:setSendSharesGate(address).selector
        || f.selector == sig:setReceiveAssetsGate(address).selector
        || f.selector == sig:setSendAssetsGate(address).selector
        || f.selector == sig:setAdapterRegistry(address).selector
        || f.selector == sig:increaseAbsoluteCap(bytes,uint256).selector
        || f.selector == sig:increaseRelativeCap(bytes,uint256).selector
        || f.selector == sig:setPerformanceFee(uint256).selector
        || f.selector == sig:setManagementFee(uint256).selector
        || f.selector == sig:setPerformanceFeeRecipient(address).selector
        || f.selector == sig:setManagementFeeRecipient(address).selector
        || f.selector == sig:setForceDeallocatePenalty(address,uint256).selector
        || f.selector == sig:increaseTimelock(bytes4,uint256).selector
        || f.selector == sig:decreaseTimelock(bytes4,uint256).selector
        || f.selector == sig:abdicate(bytes4).selector
}
{
    require abdicated(to_bytes4(f.selector));

    f@withrevert(e, args);

    assert lastReverted;
}

rule abdicatedCantBeDeabdicated(env e, method f, calldataarg args, bytes4 selector) {
    require abdicated(selector);

    f(e, args);

    assert abdicated(selector);
}

/* ABDICATION PER FUNCTION */

rule abdicateSetIsAllocator(env e, method f, calldataarg args, address account) {
    bool abdicated = abdicated(to_bytes4(sig:setIsAllocator(address, bool).selector));
    bool isAllocatorBefore = isAllocator(account);

    f(e, args);

    assert abdicated => isAllocator(account) == isAllocatorBefore;
}

rule abdicateAddAdapter(env e, method f, calldataarg args, address account) {
    bool abdicated = abdicated(to_bytes4(sig:addAdapter(address).selector));
    require !isAdapter(account);

    f(e, args);

    assert abdicated => !isAdapter(account);
}

rule abdicateRemoveAdapter(env e, method f, calldataarg args, address account) {
    bool abdicated = abdicated(to_bytes4(sig:removeAdapter(address).selector));
    require isAdapter(account);

    f(e, args);

    assert abdicated => isAdapter(account);
}

rule abdicateSetReceiveSharesGate(env e, method f, calldataarg args) {
    bool abdicated = abdicated(to_bytes4(sig:setReceiveSharesGate(address).selector));
    address receiveSharesGateBefore = receiveSharesGate();

    f(e, args);

    assert abdicated => receiveSharesGate() == receiveSharesGateBefore;
}

rule abdicateSetSendSharesGate(env e, method f, calldataarg args) {
    bool abdicated = abdicated(to_bytes4(sig:setSendSharesGate(address).selector));
    address sendSharesGateBefore = sendSharesGate();

    f(e, args);

    assert abdicated => sendSharesGate() == sendSharesGateBefore;
}

rule abdicateSetReceiveAssetsGate(env e, method f, calldataarg args) {
    bool abdicated = abdicated(to_bytes4(sig:setReceiveAssetsGate(address).selector));
    address receiveAssetsGateBefore = receiveAssetsGate();

    f(e, args);

    assert abdicated => receiveAssetsGate() == receiveAssetsGateBefore;
}

rule abdicateSetSendAssetsGate(env e, method f, calldataarg args) {
    bool abdicated = abdicated(to_bytes4(sig:setSendAssetsGate(address).selector));
    address sendAssetsGateBefore = sendAssetsGate();

    f(e, args);

    assert abdicated => sendAssetsGate() == sendAssetsGateBefore;
}

rule abdicateSetAdapterRegistry(env e, method f, calldataarg args) {
    bool abdicated = abdicated(to_bytes4(sig:setAdapterRegistry(address).selector));
    address adapterRegistryBefore = adapterRegistry();

    f(e, args);

    assert abdicated => adapterRegistry() == adapterRegistryBefore;
}

rule abdicateIncreaseAbsoluteCap(env e, method f, calldataarg args, bytes32 id) {
    bool abdicated = abdicated(to_bytes4(sig:increaseAbsoluteCap(bytes, uint256).selector));
    uint256 absoluteCapBefore = absoluteCap(id);

    f(e, args);

    assert abdicated => absoluteCap(id) <= absoluteCapBefore;
}

rule abdicateIncreaseRelativeCap(env e, method f, calldataarg args, bytes32 id) {
    bool abdicated = abdicated(to_bytes4(sig:increaseRelativeCap(bytes, uint256).selector));
    uint256 relativeCapBefore = relativeCap(id);

    f(e, args);

    assert abdicated => relativeCap(id) <= relativeCapBefore;
}

rule abdicateSetPerformanceFee(env e, method f, calldataarg args) {
    bool abdicated = abdicated(to_bytes4(sig:setPerformanceFee(uint256).selector));
    uint256 performanceFeeBefore = performanceFee();

    f(e, args);

    assert abdicated => performanceFee() == performanceFeeBefore;
}

rule abdicateSetManagementFee(env e, method f, calldataarg args) {
    bool abdicated = abdicated(to_bytes4(sig:setManagementFee(uint256).selector));
    uint256 managementFeeBefore = managementFee();

    f(e, args);

    assert abdicated => managementFee() == managementFeeBefore;
}

rule abdicateSetPerformanceFeeRecipient(env e, method f, calldataarg args) {
    bool abdicated = abdicated(to_bytes4(sig:setPerformanceFeeRecipient(address).selector));
    address performanceFeeRecipientBefore = performanceFeeRecipient();

    f(e, args);

    assert abdicated => performanceFeeRecipient() == performanceFeeRecipientBefore;
}

rule abdicateSetManagementFeeRecipient(env e, method f, calldataarg args) {
    bool abdicated = abdicated(to_bytes4(sig:setManagementFeeRecipient(address).selector));
    address managementFeeRecipientBefore = managementFeeRecipient();

    f(e, args);

    assert abdicated => managementFeeRecipient() == managementFeeRecipientBefore;
}

rule abdicateSetForceDeallocatePenalty(env e, method f, calldataarg args, address adapter) {
    bool abdicated = abdicated(to_bytes4(sig:setForceDeallocatePenalty(address, uint256).selector));
    uint256 forceDeallocatePenaltyBefore = forceDeallocatePenalty(adapter);

    f(e, args);

    assert abdicated => forceDeallocatePenalty(adapter) == forceDeallocatePenaltyBefore;
}

rule abdicateIncreaseTimelock(env e, method f, calldataarg args, bytes4 selector) {
    bool abdicated = abdicated(to_bytes4(sig:increaseTimelock(bytes4, uint256).selector));
    uint256 timelockBefore = timelock(selector);

    f(e, args);

    assert abdicated => timelock(selector) <= timelockBefore;
}

rule abdicateDecreaseTimelock(env e, method f, calldataarg args, bytes4 selector) {
    bool abdicated = abdicated(to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector));
    uint256 timelockBefore = timelock(selector);

    f(e, args);

    assert abdicated => timelock(selector) >= timelockBefore;
}

rule abdicateAbdicate(env e, method f, calldataarg args, bytes4 selector) {
    bool abdicated = abdicated(to_bytes4(sig:abdicate(bytes4).selector));
    bool abdicatedBefore = abdicated(selector);

    f(e, args);

    assert abdicated => abdicated(selector) == abdicatedBefore;
}
