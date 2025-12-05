// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Mock as ERC20;
using Utils as Utils;

definition max_int256() returns int256 = (2 ^ 255) - 1;

methods {
    function isAdapter(address) external returns bool envfree;
    function isSentinel(address) external returns bool envfree;
    function executableAt(bytes) external returns uint256 envfree;
    function getAbsoluteCap(bytes) external returns uint256 envfree;
    function getRelativeCap(bytes) external returns uint256 envfree;

    function _.deallocate(bytes, uint256 assets, bytes4, address) external =>
        nondetDeallocateSummary(assets) expect (bytes32[], int256);
    function ERC20.transferFrom(address, address, uint256) external returns bool => NONDET;
}

// Ghost copy of caps[*].allocation to be able to use quantifiers.
ghost mapping(bytes32 => uint256) ghostAllocation {
    init_state axiom forall bytes32 id. ghostAllocation[id] == 0;
}

hook Sload uint256 alloc caps[KEY bytes32 id].allocation {
    require (ghostAllocation[id] == alloc, "set ghost value to be equal to the concrete value");
}

hook Sstore caps[KEY bytes32 id].allocation uint256 realAssets (uint256 oldAllocation) {
    ghostAllocation[id] = realAssets;
}

function nondetDeallocateSummary(uint256 assets) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require (forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "assume that all returned ids are distinct");
    require (forall uint256 i. i < ids.length => ghostAllocation[ids[i]] <= max_int256(), "no overflow before");
    require (forall uint256 i. i < ids.length => ghostAllocation[ids[i]] > 0, "positive");
    require (forall uint256 i. i < ids.length => change < 0 || ghostAllocation[ids[i]] + change <= max_int256(), "no overflow after");
    require (forall uint256 i. i < ids.length => change >= 0 || ghostAllocation[ids[i]] >= -change, "no underflow after");

    return (ids, change);
}

rule sentinelCanRevoke(env e, bytes data){
    require (isSentinel(e.msg.sender), "ack");
    require (e.msg.value == 0, "ack");

    require (executableAt(data) != 0, "assume `data` is pending");

    revoke@withrevert(e, data);
    assert !lastReverted;
    assert executableAt(data) == 0;
}

rule sentinelCanDecreaseAbsoluteCap(env e, bytes idData, uint256 newAbsoluteCap) {
    require (isSentinel(e.msg.sender), "ack");
    require (e.msg.value == 0, "ack");

    require (newAbsoluteCap <= getAbsoluteCap(idData), "assume that newAbsoluteCap <= absoluteCap");

    decreaseAbsoluteCap@withrevert(e, idData, newAbsoluteCap);
    assert !lastReverted;
    assert getAbsoluteCap(idData) == newAbsoluteCap;
}

rule sentinelCanDecreaseRelativeCap(env e, bytes idData, uint256 newRelativeCap) {
    require (isSentinel(e.msg.sender), "ack");
    require (e.msg.value == 0, "ack");

    require (newRelativeCap <= getRelativeCap(idData), "assume that newRelativeCap <= relativeCap");

    decreaseRelativeCap@withrevert(e, idData, newRelativeCap);
    assert !lastReverted;
    assert getRelativeCap(idData) == newRelativeCap;
}

rule sentinelCanDeallocate(env e, address adapter, bytes data, uint256 assets){
    require (isSentinel(e.msg.sender), "ack");
    require (e.msg.value == 0, "ack");
    require (e.block.timestamp < 2^63, "safe because it corresponds to a time very far in the future");
    require (e.block.timestamp >= currentContract.lastUpdate, "safe because lastUpdate is growing and monotonic");

    require (isAdapter(adapter), "assume the adapter is valid");

    deallocate@withrevert(e, adapter, data, assets);
    assert !lastReverted;
}
