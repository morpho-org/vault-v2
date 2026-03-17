// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.balanceOf(address) external => NONDET;
    function _.realAssets() external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.canReceiveShares(address) external => NONDET;
    function _.canSendShares(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
    function accrueInterest() internal => NONDET;
    function accrueInterestView() internal returns (uint256, uint256, uint256) => NONDET;

    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e)
        => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e)
        => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
}

persistent ghost mapping(bytes32 => mapping(bytes32 => mathint)) ghostAllocationByGroupId {
    init_state axiom forall bytes32 g. forall bytes32 l. ghostAllocationByGroupId[g][l] == 0;
}

persistent ghost mapping(bytes32 => bool) ghostIsLeafId {
    init_state axiom forall bytes32 id. !ghostIsLeafId[id];
}

persistent ghost mapping(bytes32 => bool) ghostIsGroupId {
    init_state axiom forall bytes32 id. !ghostIsGroupId[id];
}

persistent ghost mapping(bytes32 => bytes32) ghostLeafToGroupId {
    init_state axiom forall bytes32 id. ghostLeafToGroupId[id] == to_bytes32(0);
}

hook Sstore currentContract.caps[KEY bytes32 id].allocation uint256 newValue (uint256 oldValue) {
    if (ghostIsLeafId[id]) {
        ghostAllocationByGroupId[ghostLeafToGroupId[id]][id] = to_mathint(newValue);
    }
}

function summaryAdapter(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require ids.length == 2, "simplification";
    require ids[0] != ids[1], "ids are distinct";

    require allocation(ids[0]) == 0 || ghostIsGroupId[ids[0]], "if ids[0] has nonzero allocation, it must be a known group id";
    require allocation(ids[1]) == 0 || ghostIsLeafId[ids[1]], "if ids[1] has nonzero allocation, it must be a known leaf id";

    require !ghostIsLeafId[ids[0]], "only ids[1] can be leafIds";
    require !ghostIsGroupId[ids[1]], "only ids[0] can be groupIds";

    // The hook updates ghostAllocationByGroupId[ghostLeafToGroupId[ids[1]]][ids[1]] when caps[ids[1]].allocation
    // is written. For the sum to track correctly, the ghost must be consistent with the actual allocation for ids[1]
    // before the hook fires. The strong invariant is assumed to hold for all leaves in the pre-state; instantiate it
    // here for the specific leaf being operated on.
    requireInvariant leafGhostConsistency(ids[1]);

    // For a new leaf (ghostIsLeafId[ids[1]] = false), ghostGroupConsistency forces
    // ghostAllocationByGroupId[ids[0]][ids[1]] = 0. Without this, the prover can freely set
    // that entry to a non-zero value X, making the hook's write a no-op to the sum (old = X, new = X)
    // while allocation(ids[0]) still increases by change — causing a sum/allocation mismatch.
    requireInvariant ghostGroupConsistency(ids[0], ids[1]);

    // The contract applies change to all ids via (int256(allocation) + change).toUint256(), which reverts on
    // underflow or overflow. Require the same here so the prover cannot pick change values that make any
    // individual allocation leave uint256 bounds, which would cause the mathint sum to exceed max_uint256.
    require to_mathint(allocation(ids[0])) + to_mathint(change) >= 0;
    require to_mathint(allocation(ids[0])) + to_mathint(change) <= max_uint256;
    require to_mathint(allocation(ids[1])) + to_mathint(change) >= 0;
    require to_mathint(allocation(ids[1])) + to_mathint(change) <= max_uint256;

    ghostIsLeafId[ids[1]] = true;
    ghostIsGroupId[ids[0]] = true;
    ghostLeafToGroupId[ids[1]] = ids[0];

    // If this leaf was already registered, its group mapping must be consistent.
    // ids() is a pure function of leaf params; ghostLeafToGroupId is set atomically with ghostIsLeafId.
    require !ghostIsLeafId[ids[1]] || ghostLeafToGroupId[ids[1]] == ids[0], "see adapterAlwaysReturnsTheSameIDsForSameData";

    return (ids, change);
}

// ids are distinct
strong invariant distinctIdTypes(bytes32 id)
    !(ghostIsLeafId[id] && ghostIsGroupId[id]);

// ghostAllocationByGroupId[groupId][leafId] is non-zero only when leafId exists and group corresponds to the leafId
strong invariant ghostGroupConsistency(bytes32 groupId, bytes32 leafId)
    !(ghostIsLeafId[leafId] && ghostLeafToGroupId[leafId] == groupId) =>
        ghostAllocationByGroupId[groupId][leafId] == 0;

// summaryAdapter always sets ghostIsGroupId[ids[0]] in the same call
// that sets ghostIsLeafId[ids[1]] and the ghostLeafToGroupId mapping. Captures that reachable states
// cannot have a registered leaf whose group id is not also registered.
strong invariant leafImpliesGroupId(bytes32 leafId)
    ghostIsLeafId[leafId] => ghostIsGroupId[ghostLeafToGroupId[leafId]];

strong invariant leafGhostConsistency(bytes32 leafId)
    ghostIsLeafId[leafId] =>
        ghostAllocationByGroupId[ghostLeafToGroupId[leafId]][leafId] == to_mathint(allocation(leafId));

strong invariant ghostAllocationBounded(bytes32 g, bytes32 l)
    ghostAllocationByGroupId[g][l] >= 0 &&
    ghostAllocationByGroupId[g][l] <= max_uint256;

// If a group is not yet registered, no leaf has been mapped to it, so its ghost sum must be zero.
// This prevents the prover from constructing pre-states where ghostIsGroupId[G] = false but the
// ghost sum for G is non-zero (from spurious pre-existing leaf entries), which would cause the
// invariant to fail when G first becomes registered during allocate.
strong invariant nonGroupHasZeroSum(bytes32 groupId)
    !ghostIsGroupId[groupId] =>
        (usum bytes32 leafId. ghostAllocationByGroupId[groupId][leafId]) == 0
{
    preserved with (env e) {
        bytes32 anyLeafId;
        // The hook only updates the sum for ghostLeafToGroupId[id], which by leafImpliesGroupId
        // is always a registered group. So unregistered groups' sums are never touched by the hook.
        requireInvariant leafImpliesGroupId(anyLeafId);
        requireInvariant ghostGroupConsistency(groupId, anyLeafId);
    }
}

strong invariant groupAllocationEqualsSumOfLeafAllocations(bytes32 groupId)
    ghostIsGroupId[groupId] =>
        to_mathint(allocation(groupId)) ==
        (usum bytes32 leafId. ghostAllocationByGroupId[groupId][leafId])
{
    preserved with (env e) {
        bytes32 anyId;
        bytes32 anyLeafId;
        requireInvariant leafGhostConsistency(anyLeafId);
        requireInvariant distinctIdTypes(anyId);
        requireInvariant ghostGroupConsistency(anyId, anyLeafId);
        requireInvariant ghostAllocationBounded(anyId, anyLeafId);
        requireInvariant leafImpliesGroupId(anyLeafId);
        requireInvariant nonGroupHasZeroSum(groupId);
    }
}

rule allocationsSumOfLeafAllocations(bytes32 groupId, bytes32 leafId) {
    require ghostIsLeafId[leafId], "leaf id has been registered via allocate or deallocate";
    require ghostIsGroupId[groupId], "group id has been registered";
    require ghostLeafToGroupId[leafId] == groupId, "ghost mapping consistency";
    requireInvariant groupAllocationEqualsSumOfLeafAllocations(groupId);
    requireInvariant leafGhostConsistency(leafId);

    bytes32 anyId; bytes32 anyLeafId;
    requireInvariant ghostAllocationBounded(anyId, anyLeafId);

    assert allocation(groupId) >= allocation(leafId),
        "group id allocation is a sum of corresponding leaf id allocations, hence >= any individual leaf allocation";
}
