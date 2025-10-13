// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Mock as ERC20;
using Utils as Utils;

definition max_int256() returns int256 = (2 ^ 255) - 1;

methods {
    function isAdapter(address) external returns (bool) envfree;
    function isSentinel(address) external returns (bool) envfree;
    function executableAt(bytes) external returns (uint256) envfree;
    function getAbsoluteCap(bytes) external returns (uint256) envfree;
    function getRelativeCap(bytes) external returns (uint256) envfree;

    function _.deallocate(bytes, uint256 assets, bytes4, address) external => nondetDeallocateSummary(assets) expect(bytes32[], int256);

    function ERC20.transferFrom(address, address, uint256) external returns (bool) => NONDET;
}

function nondetDeallocateSummary(uint256 assets) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "see distinctAdapterIds";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= max_int256(), "see allocationIsInt256";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change <= max_int256(), "see changeForDeallocateIsBoundedByAllocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0, "see changeForDeallocateIsBoundedByAllocation";

    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "assume that all ids have a positive allocation";

    return (ids, change);
}

// Check that a sentinel can always revoke.
rule sentinelCanRevoke(env e, bytes data) {
    require executableAt(data) != 0, "assume that data is pending";

    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    revoke@withrevert(e, data);
    assert !lastReverted;

    assert executableAt(data) == 0;
}

// Check that a sentinel can always decrease the absolute cap.
rule sentinelCanDecreaseAbsoluteCap(env e, bytes idData, uint256 newAbsoluteCap) {
    require executableAt(idData) != 0, "assume that idData is pending";

    require newAbsoluteCap <= getAbsoluteCap(idData), "setup call to have a newAbsoluteCap <= absoluteCap";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    decreaseAbsoluteCap@withrevert(e, idData, newAbsoluteCap);
    assert !lastReverted;

    assert getAbsoluteCap(idData) == newAbsoluteCap;
}

// Check that a sentinel can always decrease the relative cap.
rule sentinelCanDecreaseRelativeCap(env e, bytes idData, uint256 newRelativeCap) {
    require executableAt(idData) != 0, "assume that idData is pending";

    require newRelativeCap <= getRelativeCap(idData), "setup call to have a newRelativeCap <= relativeCap";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    decreaseRelativeCap@withrevert(e, idData, newRelativeCap);
    assert !lastReverted;

    assert getRelativeCap(idData) == newRelativeCap;
}

// Check that a sentinel can deallocate, assuming that the adapter has positive allocations on all ids, and assuming that the adapter deallocate call itself succeeds.
rule sentinelCanDeallocate(env e, address adapter, bytes data, uint256 assets) {
    require e.block.timestamp < 2 ^ 63, "safe because it corresponds to a time very far in the future";
    require e.block.timestamp >= currentContract.lastUpdate, "safe because lastUpdate is growing and monotonic";

    require isAdapter(adapter), "setup call to be performed on a valid adapter";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    deallocate@withrevert(e, adapter, data, assets);
    assert !lastReverted;
}
