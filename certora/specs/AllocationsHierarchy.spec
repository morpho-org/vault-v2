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

    // Replace all adapter calls with a summary that models the id structure (i.e. the leaf-group hierarchy).
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
}

// The single group id shared by every adapter, fixed across the run.
persistent ghost bytes32 globalGroupId;

// Mirrors caps[leafId].allocation for ids in the leaf set, so usum tracks the aggregate.
persistent ghost mapping(bytes32 => uint256) ghostAllocationByLeafId {
    init_state axiom forall bytes32 l. ghostAllocationByLeafId[l] == 0;
}

// The arbitrary but fixed set of leafIds. Require globalGroupId to not be a leafId.
persistent ghost mapping(bytes32 => bool) ghostIsLeafId {
    init_state axiom !ghostIsLeafId[globalGroupId];
}

// Mirror leaf allocation writes into the ghost mapping.
hook Sstore currentContract.caps[KEY bytes32 id].allocation uint256 newValue (uint256 oldValue) {
    if (ghostIsLeafId[id]) {
        ghostAllocationByLeafId[id] = newValue;
    }
}

// Adapter's allocate/deallocate summarised to return ids = [globalGroupId, leafId] and an arbitrary change.
function summaryAdapter(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require ids.length == 2, "2-slot adapter id abstraction: [globalGroupId, leafId].";
    require ids[0] == globalGroupId, "every adapter uses the global group";
    require ghostIsLeafId[ids[1]], "ids[1] is a leaf";

    // Ensures the ghost cell equals allocation(ids[1]) before the hook fires, so usum changes by exactly `change`.
    requireInvariant ghostMirrorsLeafAllocation(ids[1]);

    requireInvariant allocationIsInt256(globalGroupId);
    requireInvariant allocationIsInt256(ids[1]);

    return (ids, change);
}

// Proven in Invariants.spec, restated here to allow requireInvariant in summaryAdapter.
strong invariant allocationIsInt256(bytes32 id)
    allocation(id) <= max_int256();

// globalGroupId is never a leaf.
strong invariant globalGroupIdNotLeaf()
    !ghostIsLeafId[globalGroupId];

// The ghost cell equals the allocation for leaves and is zero otherwise.
strong invariant ghostMirrorsLeafAllocation(bytes32 leafId)
    ghostAllocationByLeafId[leafId] == (ghostIsLeafId[leafId] ? allocation(leafId) : 0);

// allocation(globalGroupId) equals the sum of all leaf allocations.
strong invariant globalGroupIdAllocationEqualsSumOfLeafAllocations()
    to_mathint(allocation(globalGroupId)) == (usum bytes32 leafId. ghostAllocationByLeafId[leafId])
    {
        preserved with (env e) {
            requireInvariant globalGroupIdNotLeaf();
        }
    }

// allocation(globalGroupId) >= allocation(leafId) for every leafId.
strong invariant globalGroupIdAllocationGteLeafAllocation(bytes32 leafId)
    ghostIsLeafId[leafId] => allocation(globalGroupId) >= allocation(leafId)
    {
        preserved {
            requireInvariant ghostMirrorsLeafAllocation(leafId);
            requireInvariant globalGroupIdAllocationEqualsSumOfLeafAllocations();
        }
    }
