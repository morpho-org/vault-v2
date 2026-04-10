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
    function accrueInterest() internal => NONDET;

    // Not strictly necessary. added to improve prover performance.
    function accrueInterestView() internal returns (uint256, uint256, uint256) => NONDET;

    // Replace all adapter calls with a ghost-updating summary that models the id structure (i.e. the leaf-group hierarchy).
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
}

// We refer to each entry in this mapping as a ghost cell.
persistent ghost mapping(bytes32 => mapping(bytes32 => uint256)) ghostAllocationByGroupId {
    init_state axiom forall bytes32 g. forall bytes32 l. ghostAllocationByGroupId[g][l] == 0;
    init_state axiom forall bytes32 g. (usum bytes32 l. ghostAllocationByGroupId[g][l]) == 0;
}

// Tracks if an id is registered as leafId
persistent ghost mapping(bytes32 => bool) ghostIsLeafId {
    init_state axiom forall bytes32 id. !ghostIsLeafId[id];
}

// Tracks if an id is registered as groupId
persistent ghost mapping(bytes32 => bool) ghostIsGroupId {
    init_state axiom forall bytes32 id. !ghostIsGroupId[id];
}

// maps leafId to groupId
persistent ghost mapping(bytes32 => bytes32) ghostLeafToGroupId {
    init_state axiom forall bytes32 id. ghostLeafToGroupId[id] == to_bytes32(0);
}

// Mirrors every leaf allocation write into the ghost mapping so the usum stays updated.
hook Sstore currentContract.caps[KEY bytes32 id].allocation uint256 newValue (uint256 oldValue) {
    if (ghostIsLeafId[id]) {
        ghostAllocationByGroupId[ghostLeafToGroupId[id]][id] = newValue;
    }
}

// Generic adapter that returns exactly two Ids that form a two-level hierarchy: groupId (index 0) and leafId (index 1).
// - groupId and leafId are distinct
// - groupId is never itself a leaf in any other adapter
// - leafId is never itself a group in any other adapter
// - a leaf's parent group never changes across calls
function summaryAdapter(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require ids.length == 2, "simplification";

    require ids[0] != ids[1], "ids are distinct";
    require !ghostIsLeafId[ids[0]], "ids[0] is not a leafId of any other adapter";
    require !ghostIsGroupId[ids[1]], "ids[1] is not a groupId of any other adapter";

    require !ghostIsLeafId[ids[1]] || ghostLeafToGroupId[ids[1]] == ids[0], "leaf maps to same group";

    // Ensures ghost cell == allocation(ids[1]) before the hook updates, so the usum changes by exactly `change`.
    requireInvariant leafGhostConsistency(ids[1]);

    // For a new id, allocation == 0.
    requireInvariant unregisteredIdHasZeroAllocation(ids[0]);
    requireInvariant unregisteredIdHasZeroAllocation(ids[1]);

    // For a new leaf, the corresponding ghost cell == 0.
    requireInvariant ghostGroupConsistency(ids[0], ids[1]);

    requireInvariant allocationIsInt256(ids[0]);
    requireInvariant allocationIsInt256(ids[1]);

    ghostIsLeafId[ids[1]] = true;
    ghostIsGroupId[ids[0]] = true;
    ghostLeafToGroupId[ids[1]] = ids[0];

    return (ids, change);
}

// Proven in Invariants.spec; restated here to allow requireInvariant in summaryAdapter.
strong invariant allocationIsInt256(bytes32 id)
    allocation(id) <= max_int256();

// No id can be both a leafId and a groupId
strong invariant distinctIdTypes(bytes32 id)
    !(ghostIsLeafId[id] && ghostIsGroupId[id]);

// A ghost cell is non-zero only if its leaf is registered and maps to that group.
strong invariant ghostGroupConsistency(bytes32 groupId, bytes32 leafId)
    !(ghostIsLeafId[leafId] && ghostLeafToGroupId[leafId] == groupId) => ghostAllocationByGroupId[groupId][leafId] == 0;

// A registered leaf's parent group is always also registered.
strong invariant leafImpliesGroupId(bytes32 leafId)
    ghostIsLeafId[leafId] => ghostIsGroupId[ghostLeafToGroupId[leafId]];

// For a registered leaf, the ghost cell must equal the allocation.
strong invariant leafGhostConsistency(bytes32 leafId)
    ghostIsLeafId[leafId] => ghostAllocationByGroupId[ghostLeafToGroupId[leafId]][leafId] == allocation(leafId);

// Unregistered groups have a zero usum shadow.
strong invariant nonGroupHasZeroSum(bytes32 groupId)
    !ghostIsGroupId[groupId] => (usum bytes32 leafId. ghostAllocationByGroupId[groupId][leafId]) == 0;

// An id that has never been registered as a leaf or group has zero allocation.
strong invariant unregisteredIdHasZeroAllocation(bytes32 id)
    !ghostIsLeafId[id] && !ghostIsGroupId[id] => allocation(id) == 0;

// The allocation of a registered group equals the usum of its leaves' ghost cells.
strong invariant groupAllocationEqualsSumOfLeafAllocations(bytes32 groupId)
    ghostIsGroupId[groupId] => to_mathint(allocation(groupId)) == (usum bytes32 leafId. ghostAllocationByGroupId[groupId][leafId])
    {
        preserved with (env e) {
            requireInvariant distinctIdTypes(groupId);
            requireInvariant nonGroupHasZeroSum(groupId);
        }
    }

// A group's allocation is the sum of all its leaves' allocations, hence it is
// always greater than or equal to any individual leaf's allocation.
rule groupAllocationGeLeafAllocation(bytes32 groupId, bytes32 leafId) {
    require ghostIsLeafId[leafId], "leafId is registered";
    require ghostLeafToGroupId[leafId] == groupId, "groupId corresponds to leafId";

    requireInvariant leafImpliesGroupId(leafId);
    requireInvariant leafGhostConsistency(leafId);
    requireInvariant groupAllocationEqualsSumOfLeafAllocations(groupId);

    assert allocation(groupId) >= allocation(leafId), "group id allocation is a sum of corresponding leaf id allocations, hence >= any individual leaf allocation";
}
