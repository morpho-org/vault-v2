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

persistent ghost mapping(bytes32 => mapping(bytes32 => mathint)) ghostAllocationByAdapterId {
    init_state axiom forall bytes32 a. forall bytes32 m. ghostAllocationByAdapterId[a][m] == 0;
}

persistent ghost mapping(bytes32 => mapping(bytes32 => mathint)) ghostAllocationByCollateralId {
    init_state axiom forall bytes32 c. forall bytes32 m. ghostAllocationByCollateralId[c][m] == 0;
}

persistent ghost mapping(bytes32 => bool) ghostIsMarketId {
    init_state axiom forall bytes32 id. !ghostIsMarketId[id];
}

persistent ghost mapping(bytes32 => bool) ghostIsAdapterId {
    init_state axiom forall bytes32 id. !ghostIsAdapterId[id];
}

persistent ghost mapping(bytes32 => bool) ghostIsCollateralId {
    init_state axiom forall bytes32 id. !ghostIsCollateralId[id];
}

persistent ghost mapping(bytes32 => bytes32) ghostMarketToAdapterId {
    init_state axiom forall bytes32 id. ghostMarketToAdapterId[id] == to_bytes32(0);
}

persistent ghost mapping(bytes32 => bytes32) ghostMarketToCollateralId {
    init_state axiom forall bytes32 id. ghostMarketToCollateralId[id] == to_bytes32(0);
}

hook Sstore currentContract.caps[KEY bytes32 id].allocation uint256 newValue (uint256 oldValue) {
    if (ghostIsMarketId[id]) {
        ghostAllocationByAdapterId[ghostMarketToAdapterId[id]][id] = to_mathint(newValue);
        ghostAllocationByCollateralId[ghostMarketToCollateralId[id]][id] = to_mathint(newValue);
    }
}

function summaryAdapter(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require ids.length == 3, "simplification";
    require ids[0] != ids[1], "see distinctMarketV1Ids";
    require ids[0] != ids[2], "see distinctMarketV1Ids";
    require ids[1] != ids[2], "see distinctMarketV1Ids";

    require allocation(ids[0]) == 0 || ghostIsAdapterId[ids[0]];
    require allocation(ids[1]) == 0 || ghostIsCollateralId[ids[1]];
    require allocation(ids[2]) == 0 || ghostIsMarketId[ids[2]];

    require !ghostIsMarketId[ids[0]], "see distinctMarketV1Ids";
    require !ghostIsMarketId[ids[1]], "see distinctMarketV1Ids";
    require !ghostIsAdapterId[ids[1]], "see distinctMarketV1Ids";
    require !ghostIsAdapterId[ids[2]], "see distinctMarketV1Ids";
    require !ghostIsCollateralId[ids[0]], "see distinctMarketV1Ids";
    require !ghostIsCollateralId[ids[2]], "see distinctMarketV1Ids";

    // If this market was already registered, its adapter and collateral mappings must be consistent with the current call.
    // Justified by adapterAlwaysReturnsTheSameIDsForSameData: ids() is a pure function of market params.
    require !ghostIsMarketId[ids[2]] || ghostMarketToAdapterId[ids[2]] == ids[0], "see adapterAlwaysReturnsTheSameIDsForSameData";
    require !ghostIsMarketId[ids[2]] || ghostMarketToCollateralId[ids[2]] == ids[1], "see adapterAlwaysReturnsTheSameIDsForSameData";

    // The hook updates ghostAllocationByAdapterId[ghostMarketToAdapterId[ids[2]]][ids[2]] when caps[ids[2]].allocation
    // is written. For the sum to track correctly, the ghost must be consistent with the actual allocation for ids[2]
    // before the hook fires. The strong invariant is assumed to hold for all markets in the pre-state; instantiate it
    // here for the specific market being operated on.
    requireInvariant marketGhostConsistency(ids[2]);

    // For a new market (ghostIsMarketId[ids[2]] = false), ghostAdapterConsistency forces
    // ghostAllocationByAdapterId[ids[0]][ids[2]] = 0. Without this, the prover can freely set
    // that entry to a non-zero value X, making the hook's write a no-op to the sum (old = X, new = X)
    // while allocation(ids[0]) still increases by change — causing a sum/allocation mismatch.
    requireInvariant ghostAdapterConsistency(ids[0], ids[2]);
    // Analogous fix for the collateral ghost sum.
    requireInvariant ghostCollateralConsistency(ids[1], ids[2]);

    // The contract applies change to all ids via (int256(allocation) + change).toUint256(), which reverts on
    // underflow or overflow. Require the same here so the prover cannot pick change values that make any
    // individual allocation leave uint256 bounds, which would cause the mathint sum to exceed max_uint256
    // while allocation(adapterId) stays bounded.
    require to_mathint(allocation(ids[0])) + to_mathint(change) >= 0;
    require to_mathint(allocation(ids[0])) + to_mathint(change) <= max_uint256;
    require to_mathint(allocation(ids[1])) + to_mathint(change) >= 0;
    require to_mathint(allocation(ids[1])) + to_mathint(change) <= max_uint256;
    require to_mathint(allocation(ids[2])) + to_mathint(change) >= 0;
    require to_mathint(allocation(ids[2])) + to_mathint(change) <= max_uint256;

    ghostIsMarketId[ids[2]] = true;
    ghostIsAdapterId[ids[0]] = true;
    ghostIsCollateralId[ids[1]] = true;
    ghostMarketToAdapterId[ids[2]] = ids[0];
    ghostMarketToCollateralId[ids[2]] = ids[1];

    return (ids, change);
}

strong invariant distinctIdTypes(bytes32 id)
    !(ghostIsMarketId[id] && ghostIsAdapterId[id]) &&
    !(ghostIsMarketId[id] && ghostIsCollateralId[id]) &&
    !(ghostIsAdapterId[id] && ghostIsCollateralId[id]);

strong invariant ghostAdapterConsistency(bytes32 adapterId, bytes32 marketId)
    !(ghostIsMarketId[marketId] && ghostMarketToAdapterId[marketId] == adapterId) =>
        ghostAllocationByAdapterId[adapterId][marketId] == 0;

strong invariant ghostCollateralConsistency(bytes32 collateralId, bytes32 marketId)
    !(ghostIsMarketId[marketId] && ghostMarketToCollateralId[marketId] == collateralId) =>
        ghostAllocationByCollateralId[collateralId][marketId] == 0;

// summaryAdapter always sets ghostIsAdapterId[ids[0]] and ghostIsCollateralId[ids[1]] in the same call
// that sets ghostIsMarketId[ids[2]] and the ghostMarketTo* mappings. This captures that reachable states
// cannot have a registered market whose adapter/collateral id is not also registered.
strong invariant marketImpliesAdapterId(bytes32 marketId)
    ghostIsMarketId[marketId] => ghostIsAdapterId[ghostMarketToAdapterId[marketId]];

strong invariant marketImpliesCollateralId(bytes32 marketId)
    ghostIsMarketId[marketId] => ghostIsCollateralId[ghostMarketToCollateralId[marketId]];

strong invariant marketGhostConsistency(bytes32 marketId)
    ghostIsMarketId[marketId] =>
        ghostAllocationByAdapterId[ghostMarketToAdapterId[marketId]][marketId] == to_mathint(allocation(marketId)) &&
        ghostAllocationByCollateralId[ghostMarketToCollateralId[marketId]][marketId] == to_mathint(allocation(marketId));

strong invariant ghostAllocationBounded(bytes32 a, bytes32 m)
    ghostAllocationByAdapterId[a][m] >= 0 &&
    ghostAllocationByAdapterId[a][m] <= max_uint256 &&
    ghostAllocationByCollateralId[a][m] >= 0 &&
    ghostAllocationByCollateralId[a][m] <= max_uint256;

// If an adapter is not yet registered, no market has been mapped to it, so its ghost sum must be zero.
// This prevents the prover from constructing pre-states where ghostIsAdapterId[A] = false but the
// ghost sum for A is non-zero (from spurious pre-existing market entries), which would cause the
// invariant to fail when A first becomes registered during allocate.
strong invariant nonAdapterHasZeroSum(bytes32 adapterId)
    !ghostIsAdapterId[adapterId] =>
        (usum bytes32 marketId. ghostAllocationByAdapterId[adapterId][marketId]) == 0
{
    preserved with (env e) {
        bytes32 anyMarketId;
        // The hook only updates the sum for ghostMarketToAdapterId[id], which by marketImpliesAdapterId
        // is always a registered adapter. So unregistered adapters' sums are never touched by the hook.
        requireInvariant marketImpliesAdapterId(anyMarketId);
        requireInvariant ghostAdapterConsistency(adapterId, anyMarketId);
    }
}

// Analogous to nonAdapterHasZeroSum: if a collateral id is not yet registered, its ghost sum must be zero.
strong invariant nonCollateralHasZeroSum(bytes32 collateralId)
    !ghostIsCollateralId[collateralId] =>
        (usum bytes32 marketId. ghostAllocationByCollateralId[collateralId][marketId]) == 0
{
    preserved with (env e) {
        bytes32 anyMarketId;
        requireInvariant marketImpliesCollateralId(anyMarketId);
        requireInvariant ghostCollateralConsistency(collateralId, anyMarketId);
    }
}

strong invariant adapterAllocationEqualsSumOfMarketAllocations(bytes32 adapterId)
    ghostIsAdapterId[adapterId] =>
        to_mathint(allocation(adapterId)) ==
        (usum bytes32 marketId. ghostAllocationByAdapterId[adapterId][marketId])
{
    preserved with (env e) {
        bytes32 anyId;
        bytes32 anyMarketId;
        requireInvariant marketGhostConsistency(anyMarketId);
        requireInvariant distinctIdTypes(anyId);
        requireInvariant ghostAdapterConsistency(anyId, anyMarketId);
        requireInvariant ghostAllocationBounded(anyId, anyMarketId);
        requireInvariant marketImpliesAdapterId(anyMarketId);
        // When adapterId transitions false→true during the first allocate, the pre-state ghost sum
        // must be zero so the post-state sum equals change = allocation(adapterId)_post.
        requireInvariant nonAdapterHasZeroSum(adapterId);
    }
}

strong invariant collateralAllocationEqualsSumOfMarketAllocations(bytes32 collateralId)
    ghostIsCollateralId[collateralId] =>
        to_mathint(allocation(collateralId)) ==
        (usum bytes32 marketId. ghostAllocationByCollateralId[collateralId][marketId])
{
    preserved with (env e) {
        bytes32 anyId;
        bytes32 anyMarketId;
        requireInvariant marketGhostConsistency(anyMarketId);
        requireInvariant distinctIdTypes(anyId);
        requireInvariant ghostCollateralConsistency(anyId, anyMarketId);
        requireInvariant ghostAllocationBounded(anyId, anyMarketId);
        requireInvariant marketImpliesCollateralId(anyMarketId);
        requireInvariant nonCollateralHasZeroSum(collateralId);
    }
}

rule allocationsSumOfMarketIdAllocations(bytes32 adapterId, bytes32 collateralId, bytes32 marketId) {
    require ghostIsMarketId[marketId], "market id has been registered via allocate or deallocate";
    require ghostIsAdapterId[adapterId], "adapter id has been registered";
    require ghostIsCollateralId[collateralId], "collateral id has been registered";
    require ghostMarketToAdapterId[marketId] == adapterId, "ghost mapping consistency";
    require ghostMarketToCollateralId[marketId] == collateralId, "ghost mapping consistency";

    requireInvariant adapterAllocationEqualsSumOfMarketAllocations(adapterId);
    requireInvariant collateralAllocationEqualsSumOfMarketAllocations(collateralId);

    assert allocation(adapterId) >= allocation(marketId),
        "adapter id allocation is a sum of market id allocations, hence >= any individual market allocation";
    assert allocation(collateralId) >= allocation(marketId),
        "collateral token id allocation is a sum of market id allocations, hence >= any individual market allocation";
}
