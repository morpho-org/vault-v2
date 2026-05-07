// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function accrueInterestView() internal returns (uint256, uint256, uint256) => NONDET;

    // Replace all adapter calls with a summary that models the id structure (i.e. the leaf-group hierarchy).
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
}

definition max_int256() returns mathint = (2 ^ 255) - 1;

// An abitrary but fixed group id.
persistent ghost bytes32 groupId;

// The arbitrary but fixed set of leaf ids. Requires group id to not be a leaf id.
persistent ghost mapping(bytes32 => bool) isLeaf {
    init_state axiom !isLeaf[groupId];
}

// Mirrors caps[id].allocation for id in the leaf set, so usum tracks the aggregate.
persistent ghost mapping(bytes32 => uint256) leafAllocation {
    init_state axiom forall bytes32 id. leafAllocation[id] == 0;
}

// Mirror leaf allocation writes into the ghost mapping.
hook Sstore currentContract.caps[KEY bytes32 id].allocation uint256 newValue (uint256 oldValue) {
    if (isLeaf[id]) {
        leafAllocation[id] = newValue;
    }
}

// Adapter's allocate/deallocate summarised to return ids = [groupId, leaf] and an arbitrary change.
function summaryAdapter(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require ids.length == 2, "2-slot adapter id abstraction: [groupId, leaf].";
    require ids[0] == groupId, "every adapter uses the group";
    require isLeaf[ids[1]], "ids[1] is a leaf";

    requireInvariant ghostMirrorsLeafAllocation(ids[1]);
    requireInvariant allocationIsInt256(groupId);
    requireInvariant allocationIsInt256(ids[1]);

    return (ids, change);
}

// Proven in Invariants.spec, restated here to allow requireInvariant in summaryAdapter.
strong invariant allocationIsInt256(bytes32 id)
    allocation(id) <= max_int256();

// The groupId is never a leaf.
strong invariant groupIdNotLeaf()
    !isLeaf[groupId];

// The ghost cell equals the allocation for leaves and is zero otherwise.
strong invariant ghostMirrorsLeafAllocation(bytes32 id)
    leafAllocation[id] == (isLeaf[id] ? allocation(id) : 0);

// The group allocation equals the sum of all leaf allocations.
strong invariant groupAllocationEqualsSumOfLeafAllocations()
    allocation(groupId) == (usum bytes32 id. leafAllocation[id])
    {
        preserved with (env e) {
            requireInvariant groupIdNotLeaf();
        }
    }

// The group allocation is greater than or equal to the allocation for any leaf.
rule groupAllocationGteLeafAllocation(bytes32 id) {
    requireInvariant ghostMirrorsLeafAllocation(id);
    requireInvariant groupAllocationEqualsSumOfLeafAllocations();

    assert isLeaf[id] => allocation(groupId) >= allocation(id);
}
