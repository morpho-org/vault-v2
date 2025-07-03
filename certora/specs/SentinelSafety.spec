// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Mock as ERC20;

methods {
    function isAdapter(address) external returns bool  envfree;
    function isSentinel(address) external returns bool  envfree;
    function executableAt(bytes) external returns uint256 envfree;
    function getAbsoluteCap(bytes) external returns uint256 envfree;
    function getRelativeCap(bytes) external returns uint256 envfree;

    function _.deallocate(bytes, uint256 assets, bytes4, address) external =>
        nondetAllocatorSummary(assets) expect (bytes32[], uint256);
    function ERC20.transferFrom(address, address, uint256) external returns bool => NONDET;
}

// Ghost copy of caps[*].allocation for quantification.
ghost mapping(bytes32 => uint256) ghostAllocation {
    init_state axiom forall bytes32 id. ghostAllocation[id] == 0;
}

hook Sload uint256 alloc caps[KEY bytes32 id].allocation {
    require (ghostAllocation[id] == alloc, "set ghost value to be equal to the concrete value");
}

hook Sstore caps[KEY bytes32 id].allocation uint256 newAllocation (uint256 oldAllocation) {
    ghostAllocation[id] = newAllocation;
}

function nondetUintSummary() returns uint256 {
    uint256 value;
    return value;
}

function nondetBoolSummary() returns bool {
    bool value;
    return value;
}

function nondetAllocatorSummary(uint256 assets) returns (bytes32[], uint256) {
    bytes32[] ids;
    uint256 interest;

    require (forall uint256 i. forall uint256 j. i < ids.length => i < j && j < ids.length => ids[j] != ids[i], "assume that all returned ids are unique");
    require (forall uint256 i. i < ids.length && ghostAllocation[ids[i]] >= assets && ghostAllocation[ids[i]] > 0, "assume that all returned ids have realistic allocations");
    require (forall uint256 i. i < ids.length && (ghostAllocation[ids[i]] + interest) <= max_uint256, "assume that the allocated amount plus the interest can't overflow");

    return (ids, interest);
}

rule sentinelCanRevoke(env e, bytes data){
    require (isSentinel(e.msg.sender), "setup the call to be performed by a sentinel address");
    require (e.msg.value == 0, "setup the call to have no ETH value");

    require (executableAt(data) != 0, "setup the call so that the timelock is revokable");

    revoke@withrevert(e, data);
    assert !lastReverted;
    assert executableAt(data) == 0;
}

rule sentinelCanDecreaseAbsoluteCap(env e, bytes idData, uint256 newAbsoluteCap) {
    require (isSentinel(e.msg.sender), "setup the call to be performed by a sentinel address");
    require (e.msg.value == 0, "setup the call to have no ETH value");

    require (newAbsoluteCap <= getAbsoluteCap(idData), "assume the new absolute cap is valid");

    decreaseAbsoluteCap@withrevert(e, idData, newAbsoluteCap);
    assert !lastReverted;
    assert getAbsoluteCap(idData) == newAbsoluteCap;
}

rule sentinelCanDecreaseRelativeCap(env e, bytes idData, uint256 newRelativeCap) {
    require (isSentinel(e.msg.sender), "setup the call to be performed by a sentinel address");
    require (e.msg.value == 0, "setup the call to have no ETH value");

    require (newRelativeCap <= getRelativeCap(idData), "assume the new relative cap is valid");

    decreaseRelativeCap@withrevert(e, idData, newRelativeCap);
    assert !lastReverted;
    assert getRelativeCap(idData) == newRelativeCap;
}

rule sentinelCanDeallocate(env e, address adapter, bytes data, uint256 assets){
    require (e.block.timestamp < 2^63, "bound the timestamp to a time very far in the future");
    require (e.block.timestamp >= currentContract.lastUpdate, "lastUpdate is growing and monotonic");
    require (isSentinel(e.msg.sender), "setup the call to be performed by a sentinel address");
    require (e.msg.value == 0, "setup the call to have no ETH value");

    require (isAdapter(adapter), "assume the adapter is valid");

    // Assume interest accrual doesn't fail during deallocation.
    accrueInterest(e);

    deallocate@withrevert(e, adapter, data, assets);
    assert !lastReverted;
}

rule ownerCanDeallocate(env e, address adapter, bytes data, uint256 assets){
    require (e.block.timestamp < 2^63, "bound the timestamp to a time very far in the future");
    require (e.block.timestamp >= currentContract.lastUpdate, "lastUpdate is growing and monotonic");
    require (currentContract.owner == e.msg.sender, "setup the call to be performed by the owner of the contract");
    require (!isSentinel(currentContract.owner), "assume the owner is not a sentinel");
    require (e.msg.value == 0, "setup the call to have no ETH value");

    require (isAdapter(adapter), "assume the adapter is valid");

    // Assume interest accrual doesn't fail during deallocation.
    accrueInterest(e);

    setIsSentinel@withrevert(e, currentContract.owner, true);
    assert !lastReverted;
    assert isSentinel(currentContract.owner);

    deallocate@withrevert(e, adapter, data, assets);
    assert !lastReverted;
}
