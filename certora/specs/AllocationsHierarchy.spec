// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

definition max_int256() returns mathint = (2 ^ 255) - 1;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.balanceOf(address) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.canReceiveShares(address) external => NONDET;
    function _.canSendShares(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
    function accrueInterest() internal => NONDET;
    function accrueInterestView() internal returns (uint256, uint256, uint256) => NONDET;

    // Replace every adapter call with a summary that models the (groupId, leafId) hierarchy.
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
}

// Mirrors caps[leaf].allocation per group, so usum tracks per-group aggregates.
persistent ghost mapping(bytes32 => mapping(bytes32 => uint256)) ghostAllocationByGroupId {
    init_state axiom forall bytes32 g. forall bytes32 l. ghostAllocationByGroupId[g][l] == 0;
    init_state axiom forall bytes32 g. (usum bytes32 l. ghostAllocationByGroupId[g][l]) == 0;
}

// The arbitrary but fixed set of leafIds.
persistent ghost mapping(bytes32 => bool) ghostIsLeafId;

// The arbitrary but fixed set of groupIds. Disjoint from the leaf set.
persistent ghost mapping(bytes32 => bool) ghostIsGroupId {
    axiom forall bytes32 id. !(ghostIsLeafId[id] && ghostIsGroupId[id]);
}

// The arbitrary but fixed leaf -> group map. Each leaf maps to a registered group.
persistent ghost mapping(bytes32 => bytes32) ghostLeafToGroupId {
    axiom forall bytes32 l. ghostIsLeafId[l] => ghostIsGroupId[ghostLeafToGroupId[l]];
}

// Define `ghostAllocationByGroupId` updates.
hook Sstore currentContract.caps[KEY bytes32 id].allocation uint256 newValue (uint256 oldValue) {
    if (ghostIsLeafId[id]) {
        ghostAllocationByGroupId[ghostLeafToGroupId[id]][id] = newValue;
    }
}

// Adapter's allocate/deallocate summarised to return ids = [groupId, leafId] and an arbitrary change.
function summaryAdapter(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require ids.length == 2, "simplification";
    require ghostIsGroupId[ids[0]], "ids[0] is a group";
    require ghostIsLeafId[ids[1]], "ids[1] is a leaf";
    require ghostLeafToGroupId[ids[1]] == ids[0], "leaf belongs to ids[0]'s group";

    // Pin ghost[parent][ids[1]] == caps[ids[1]] before VaultV2 writes caps[ids[1]]. The hook's overwrite then advances usum by exactly `change`.
    requireInvariant leafGhostMatchesAllocation(ids[1]);

    requireInvariant allocationIsInt256(ids[0]);
    requireInvariant allocationIsInt256(ids[1]);

    return (ids, change);
}

// Proven in Invariants.spec, restated here to allow requireInvariant in summaryAdapter.
strong invariant allocationIsInt256(bytes32 id)
    allocation(id) <= max_int256();

// ghostAllocationByGroupId at a leaf's parent group equals the leaf's allocation, and is zero for non-leaves.
strong invariant leafGhostMatchesAllocation(bytes32 leafId)
    ghostAllocationByGroupId[ghostLeafToGroupId[leafId]][leafId] == (ghostIsLeafId[leafId] ? allocation(leafId) : 0);

// ghostAllocationByGroupId at non-matching (group, leaf) pairs are zero.
strong invariant nonMatchingCellIsZero(bytes32 groupId, bytes32 leafId)
    !(ghostIsLeafId[leafId] && ghostLeafToGroupId[leafId] == groupId) => ghostAllocationByGroupId[groupId][leafId] == 0;

// Per-group usum is zero for groups outside the group set.
strong invariant unregisteredGroupHasZeroGhostSum(bytes32 groupId)
    !ghostIsGroupId[groupId] => (usum bytes32 l. ghostAllocationByGroupId[groupId][l]) == 0;

// allocation(groupId) equals the sum of its leaves' allocations.
strong invariant groupAllocationEqualsSumOfLeafAllocations(bytes32 groupId)
    ghostIsGroupId[groupId] => to_mathint(allocation(groupId)) == (usum bytes32 l. ghostAllocationByGroupId[groupId][l])
    {
        preserved with (env e) {
            bytes32 leafId;
            requireInvariant unregisteredGroupHasZeroGhostSum(groupId);
            requireInvariant nonMatchingCellIsZero(groupId, leafId);
            requireInvariant leafGhostMatchesAllocation(leafId);
        }
    }

// allocation(groupId) >= allocation(leafId) for any leaf belonging to that group.
rule groupAllocationGteLeafAllocation(bytes32 groupId, bytes32 leafId) {
    require ghostIsLeafId[leafId], "leafId is in the leaf set";
    require ghostLeafToGroupId[leafId] == groupId, "leaf belongs to groupId";

    requireInvariant leafGhostMatchesAllocation(leafId);
    requireInvariant groupAllocationEqualsSumOfLeafAllocations(groupId);

    assert allocation(groupId) >= allocation(leafId);
}
