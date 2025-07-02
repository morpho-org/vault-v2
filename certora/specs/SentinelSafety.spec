// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using SafeERC20Lib as SafeERC20Lib;

methods {
    function isAdapter(address) external returns bool  envfree;
    function isSentinel(address) external returns bool  envfree;
    function executableAt(bytes) external returns uint256 envfree;
    function getAbsoluteCap(bytes) external returns uint256 envfree;
    function getRelativeCap(bytes) external returns uint256 envfree;

    function _.canReceiveShares(address) external
        => nondetBoolSummary() expect bool;
    function _.deallocate(bytes, uint256 assets, bytes4, address) external =>
         nondetAllocatorSummary(assets) expect (bytes32[], uint256);
    function _.interestPerSecond(uint256, uint256) external =>
        nondetUintSummary() expect uint256;

    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
}

ghost mapping(bytes32 => uint256) ghostAllocation {
    init_state axiom forall bytes32 id. ghostAllocation[id] == 0;
}

hook Sload uint256 alloc caps[KEY bytes32 id].allocation {
    require ghostAllocation[id] == alloc;
}

hook Sstore caps[KEY bytes32 id].allocation uint256 newAllocation (uint256 _) {
    ghostAllocation[id] = newAllocation;
}

function nondetAccrueInterestSummary() returns (uint256, uint256, uint256) {
    uint256[] interests;
    return (interests[0], interests[1], interests[2]);
}

function nondetAllocatorSummary(uint256 assets) returns (bytes32[], uint256) {
    bytes32[] ids;
    uint256 interest;

    //require forall uint256 i. forall uint256 j. i != j && ids[i] != ids[j];
    require forall uint256 i. forall uint256 j. i < ids.length => i < j && j < ids.length => ids[j] != ids[i];
    require forall uint256 i. i < ids.length && ghostAllocation[ids[i]] >= assets;
    require forall uint256 i. i < ids.length && (ghostAllocation[ids[i]] + interest) <= max_uint256;

    return (ids, interest);
}

function nondetUintSummary() returns uint256 {
    uint256 value;
    return value;
}

function nondetBoolSummary() returns bool {
    bool value;
    return value;
}

rule sentinelCanRevoke(env e, bytes data){
    // Setup the caller to be a sentinel.
    require isSentinel(e.msg.sender);

    uint256 executableAtBefore =  executableAt(data);

    revoke@withrevert(e, data);
    assert lastReverted <=> executableAtBefore == 0 || e.msg.value != 0;
}

rule sentinelCanDecreaseAbsoluteCap(env e, bytes idData, uint256 newAbsoluteCap) {
    // Setup the caller to be a sentinel.
    require isSentinel(e.msg.sender);

    uint256 absoluteCapBefore = getAbsoluteCap(idData);

    decreaseAbsoluteCap@withrevert(e, idData, newAbsoluteCap);
    assert lastReverted <=> absoluteCapBefore < newAbsoluteCap  || e.msg.value != 0;
}

rule sentinelCanDecreaseRelativeCap(env e, bytes idData, uint256 newRelativeCap) {
    // Setup the caller to be a sentinel.
    require isSentinel(e.msg.sender);

    uint256 relativeCapBefore = getRelativeCap(idData);

    decreaseRelativeCap@withrevert(e, idData, newRelativeCap);
    assert lastReverted <=> relativeCapBefore < newRelativeCap  || e.msg.value != 0;
}

rule sentinelCanDeallocate(env e, address adapter, bytes data, uint256 assets){
    // Safe require as it's some time very far into the future.
    require e.block.timestamp < 2^63;
    // Safe require as lastUpdate is growing and monotonic
    require e.block.timestamp >= currentContract.lastUpdate;
    // Setup the caller to be a sentinel.
    require isSentinel(e.msg.sender);

    require assets > 0;

    require isAdapter(adapter);

    accrueInterest@withrevert(e);
    bool accrueInterestReverted = lastReverted;

    deallocate@withrevert(e, adapter, data, assets);
    bool deallocateReverted = lastReverted;

    require !accrueInterestReverted;
    assert!deallocateReverted ;
}
