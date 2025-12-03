// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;

methods {
    function allocation(MorphoMarketV1AdapterV2.MarketParams memory marketParams) internal returns (uint256) => ghostAllocation[Utils.id(marketParams)];

    function Utils.id(MorphoMarketV1AdapterV2.MarketParams) external returns (MorphoMarketV1AdapterV2.Id) envfree;
    function Utils.decodeMarketParams(bytes) external returns (MorphoMarketV1AdapterV2.MarketParams) envfree;
}

// Mimics the allocation in the vault corresponding to the function allocation of the MorphoMarketV1AdapterV2.
// Note: the key is a market id, not the adapter id corresponding to the market params.
ghost mapping (MorphoMarketV1AdapterV2.Id => uint256) ghostAllocation;

function morphoMarketV1AdapterWrapperSummary(env e, bool isAllocateCall, bytes data, uint256 assets) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    bytes4 selector;
    address sender;
    if (isAllocateCall) {
        ids, change = allocate(e, data, assets, selector, sender);
    } else {
        ids, change = deallocate(e, data, assets, selector, sender);
    }
    MorphoMarketV1AdapterV2.MarketParams marketParams = Utils.decodeMarketParams(data);
    MorphoMarketV1AdapterV2.Id marketId = Utils.id(marketParams);
    // Safe require because it is the same computation as in the implementation `(int256(allocation) + change).toUint256()`, except for the cast of the allocation to int256 which is guaranteed to be safe by the rule allocationIsInt256.
    ghostAllocation[marketId] = require_uint256(ghostAllocation[marketId] + change);
    return (ids, change);
}

// Prove that if a market has no allocation, it is not in the market ids list.
strong invariant marketIdsWithNoAllocationIsNotInMarketIds()
    forall MorphoMarketV1AdapterV2.Id marketId.
    forall uint256 i. i < currentContract.marketIds.length => ghostAllocation[marketId] == 0 => currentContract.marketIds[i] != marketId
filtered {
    f -> f.selector != sig:allocate(bytes, uint256, bytes4, address).selector && f.selector != sig:deallocate(bytes, uint256, bytes4, address).selector
}
{
    preserved {
        requireInvariant distinctMarketIdsInList();
    }
}

// Rule to be able to summarize allocate and deallocate calls.
rule marketIdsWithNoAllocationIsNotInMarketIdsAllocateAndDeallocate(env e, bytes data, uint256 assets) {
    require forall MorphoMarketV1AdapterV2.Id marketId.
    forall uint256 i. i < currentContract.marketIds.length => ghostAllocation[marketId] == 0 => currentContract.marketIds[i] != marketId;

    bool isAllocateCall;
    morphoMarketV1AdapterWrapperSummary(e, isAllocateCall, data, assets);

    assert forall MorphoMarketV1AdapterV2.Id marketId.
    forall uint256 i. i < currentContract.marketIds.length => ghostAllocation[marketId] == 0 => currentContract.marketIds[i] != marketId;
}

// Prove that marketIds contains distinct elements.
strong invariant distinctMarketIdsInList()
    forall uint256 i. forall uint256 j. i < j => j < currentContract.marketIds.length => currentContract.marketIds[j] != currentContract.marketIds[i]
filtered {
    f -> f.selector != sig:allocate(bytes, uint256, bytes4, address).selector && f.selector != sig:deallocate(bytes, uint256, bytes4, address).selector
}
{
    preserved {
        requireInvariant marketIdsWithNoAllocationIsNotInMarketIds();
    }
}

// Rule to be able to summarize allocate and deallocate calls.
rule distinctMarketIdsInListAllocateAndDeallocate(env e, bytes data, uint256 assets) {
    require forall uint256 i. forall uint256 j. i < j => j < currentContract.marketIds.length => currentContract.marketIds[j] != currentContract.marketIds[i];

    bool isAllocateCall;
    morphoMarketV1AdapterWrapperSummary(e, isAllocateCall, data, assets);

    assert forall uint256 i. forall uint256 j. i < j => j < currentContract.marketIds.length => currentContract.marketIds[j] != currentContract.marketIds[i];
}
