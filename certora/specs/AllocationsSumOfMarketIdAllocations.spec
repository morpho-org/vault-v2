// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e)
        => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e)
        => summaryAdapter(e, data, assets, selector, sender) expect(bytes32[], int256);
}

ghost mapping(bytes32 => mapping(bytes32 => mathint)) ghostAllocationByAdapterId {
    init_state axiom forall bytes32 a. forall bytes32 m. ghostAllocationByAdapterId[a][m] == 0;
}

ghost mapping(bytes32 => mapping(bytes32 => mathint)) ghostAllocationByCollateralId {
    init_state axiom forall bytes32 c. forall bytes32 m. ghostAllocationByCollateralId[c][m] == 0;
}

ghost mapping(bytes32 => bool) ghostIsMarketId {
    init_state axiom forall bytes32 id. !ghostIsMarketId[id];
}

ghost mapping(bytes32 => bytes32) ghostMarketToAdapterId {
    init_state axiom forall bytes32 id. ghostMarketToAdapterId[id] == to_bytes32(0);
}

ghost mapping(bytes32 => bytes32) ghostMarketToCollateralId {
    init_state axiom forall bytes32 id. ghostMarketToCollateralId[id] == to_bytes32(0);
}

ghost mapping(bytes32 => bool) ghostIsAdapterId {
    init_state axiom forall bytes32 id. !ghostIsAdapterId[id];
}

ghost mapping(bytes32 => bool) ghostIsCollateralId {
    init_state axiom forall bytes32 id. !ghostIsCollateralId[id];
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

    require ids.length == 3, "see IdsMorphoMarketV1AdapterV2";
    require ids[0] != ids[1], "see distinctMarketV1Ids";
    require ids[0] != ids[2], "see distinctMarketV1Ids";
    require ids[1] != ids[2], "see distinctMarketV1Ids";

    require allocation(ids[0]) == 0 || ghostIsAdapterId[ids[0]];
    require allocation(ids[1]) == 0 || ghostIsCollateralId[ids[1]];
    require allocation(ids[2]) == 0 || ghostIsMarketId[ids[2]];

    // Adapter and collateral ids are not market ids; prevents spurious hook updates when caps[ids[0/1]].allocation is stored.
    require !ghostIsMarketId[ids[0]], "see distinctMarketV1Ids";
    require !ghostIsMarketId[ids[1]], "see distinctMarketV1Ids";

    // If this market was already registered, its adapter and collateral mappings must be consistent with the current call.
    // Justified by adapterAlwaysReturnsTheSameIDsForSameData: ids() is a pure function of market params.
    require !ghostIsMarketId[ids[2]] || ghostMarketToAdapterId[ids[2]] == ids[0], "see adapterAlwaysReturnsTheSameIDsForSameData";
    require !ghostIsMarketId[ids[2]] || ghostMarketToCollateralId[ids[2]] == ids[1], "see adapterAlwaysReturnsTheSameIDsForSameData";

    ghostIsMarketId[ids[2]] = true;
    ghostMarketToAdapterId[ids[2]] = ids[0];
    ghostMarketToCollateralId[ids[2]] = ids[1];
    ghostIsAdapterId[ids[0]] = true;
    ghostIsCollateralId[ids[1]] = true;

    return (ids, change);
}

strong invariant adapterAllocationEqualsSumOfMarketAllocations(bytes32 adapterId)
    ghostIsAdapterId[adapterId] =>
        to_mathint(allocation(adapterId)) ==
        (sum bytes32 marketId. ghostAllocationByAdapterId[adapterId][marketId]);

strong invariant collateralAllocationEqualsSumOfMarketAllocations(bytes32 collateralId)
    ghostIsCollateralId[collateralId] =>
        to_mathint(allocation(collateralId)) ==
        (sum bytes32 marketId. ghostAllocationByCollateralId[collateralId][marketId]);

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
