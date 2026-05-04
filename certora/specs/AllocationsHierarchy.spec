// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

definition max_int256() returns mathint = (2 ^ 255) - 1;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // assume the following functions return arbitrary value but do not modify the relevant storage for this rule.
    function _.balanceOf(address) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.canReceiveShares(address) external => NONDET;
    function _.canSendShares(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
    function accrueInterestView() internal returns (uint256, uint256, uint256) => NONDET;

    // Summary model: one group per adapter, and if a leaf is returned then its group is returned too.
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(calledContract, e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(calledContract, e, data, assets, selector, sender) expect(bytes32[], int256);
}

// True ghost state. `ghostAllocationByGroupId[groupId]` tracks the aggregate contribution to `groupId`.
// The hook updates it by the leaf delta `newValue - oldValue`.
persistent ghost mapping(bytes32 => mathint) ghostAllocationByGroupId {
    init_state axiom forall bytes32 g. ghostAllocationByGroupId[g] == 0;
}

// Global aggregate of all leaf allocations across every adapter/group.
persistent ghost mathint ghostTotalLeafAllocation {
    init_state axiom ghostTotalLeafAllocation == 0;
}

// Global aggregate of all group allocations (parallel mirror, updated on group writes).
persistent ghost mathint ghostTotalGroupAllocation {
    init_state axiom ghostTotalGroupAllocation == 0;
}

// Tracks if an id is registered as leafId
persistent ghost mapping(bytes32 => bool) ghostIsLeafId {
    init_state axiom forall bytes32 id. !ghostIsLeafId[id];
}

// Tracks if an id is registered as groupId
persistent ghost mapping(bytes32 => bool) ghostIsGroupId {
    init_state axiom forall bytes32 id. !ghostIsGroupId[id];
}

// Maps each adapter to its unique groupId in this spec model.
persistent ghost mapping(address => bytes32) ghostAdapterToGroupId {
    init_state axiom forall address adapter. ghostAdapterToGroupId[adapter] == to_bytes32(0);
}

// Maps each leafId to the groupId returned with it. Immutable across calls.
persistent ghost mapping(bytes32 => bytes32) ghostLeafToGroupId {
    init_state axiom forall bytes32 id. ghostLeafToGroupId[id] == to_bytes32(0);
}

// Defines how the true ghost group sum is updated on leaf allocation writes.
hook Sstore currentContract.caps[KEY bytes32 id].allocation uint256 newValue (uint256 oldValue) {
    if (ghostIsLeafId[id]) {
        ghostAllocationByGroupId[ghostLeafToGroupId[id]] = ghostAllocationByGroupId[ghostLeafToGroupId[id]] - oldValue + newValue;
        ghostTotalLeafAllocation = ghostTotalLeafAllocation - oldValue + newValue;
    }
    if (ghostIsGroupId[id]) {
        ghostTotalGroupAllocation = ghostTotalGroupAllocation - oldValue + newValue;
    }
}

// Simplified hierarchy:
// - ids[0] is the groupId and ids[1] is the leafId
// - one group per adapter
// - if a leaf is returned, its group is returned too
// - the leaf/group pair is immutable across calls
// - unlike the full setup (including Midnight), a leaf cannot also be a group and does not belong to multiple groups
function summaryAdapter(address adapter, env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require ids.length == 2, "simplification: one group per adapter in this spec";

    require ids[0] != ids[1], "ids are distinct";
    require !ghostIsLeafId[ids[0]], "ids[0] is not a leafId of any other adapter";
    require !ghostIsGroupId[ids[1]], "ids[1] is not a groupId of any other adapter";

    require ghostAdapterToGroupId[adapter] == to_bytes32(0) || ghostAdapterToGroupId[adapter] == ids[0], "adapter maps to same group";
    require !ghostIsLeafId[ids[1]] || ghostLeafToGroupId[ids[1]] == ids[0], "leaf maps to same group";

    // For a new id, allocation == 0.
    requireInvariant unregisteredIdHasZeroAllocation(ids[0]);
    requireInvariant unregisteredIdHasZeroAllocation(ids[1]);

    // For a new group, the aggregate ghost contribution is 0.
    requireInvariant unregisteredGroupHasZeroGhostAllocation(ids[0]);

    requireInvariant allocationIsInt256(ids[0]);
    requireInvariant allocationIsInt256(ids[1]);

    ghostIsLeafId[ids[1]] = true;
    ghostIsGroupId[ids[0]] = true;
    ghostAdapterToGroupId[adapter] = ids[0];
    ghostLeafToGroupId[ids[1]] = ids[0];

    return (ids, change);
}

// Proven in Invariants.spec; restated here to allow requireInvariant in summaryAdapter.
strong invariant allocationIsInt256(bytes32 id)
    allocation(id) <= max_int256();

// Simplification: an id cannot be both a leafId and a groupId.
strong invariant distinctIdTypes(bytes32 id)
    !(ghostIsLeafId[id] && ghostIsGroupId[id]);

// A registered leaf's parent group is always also registered.
strong invariant registeredLeafImpliesRegisteredGroup(bytes32 leafId)
    ghostIsLeafId[leafId] => ghostIsGroupId[ghostLeafToGroupId[leafId]];

// Unregistered groups have a zero ghost-tracked aggregate.
strong invariant unregisteredGroupHasZeroGhostAllocation(bytes32 groupId)
    !ghostIsGroupId[groupId] => ghostAllocationByGroupId[groupId] == 0;

// An id that has never been registered as a leaf or group has zero allocation.
strong invariant unregisteredIdHasZeroAllocation(bytes32 id)
    !ghostIsLeafId[id] && !ghostIsGroupId[id] => allocation(id) == 0;

// A registered group's allocation equals its ghost-tracked aggregate.
strong invariant groupAllocationEqualsGhostAllocation(bytes32 groupId)
    ghostIsGroupId[groupId] => to_mathint(allocation(groupId)) == ghostAllocationByGroupId[groupId]
    {
        preserved with (env e) {
            requireInvariant distinctIdTypes(groupId);
            requireInvariant unregisteredGroupHasZeroGhostAllocation(groupId);
        }
    }

// Global: total leaf allocation equals total group allocation.
strong invariant totalLeafEqualsTotalGroup()
    ghostTotalLeafAllocation == ghostTotalGroupAllocation;
