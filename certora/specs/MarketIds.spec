// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using MorphoMarketV1Adapter as MorphoMarketV1Adapter;

methods {
    function allocation(MorphoMarketV1Adapter.MarketParams memory marketParams) internal returns (uint256) => ghostAllocation[Utils.id(marketParams)];

    function allocate(bytes data, uint256 assets, bytes4, address) external returns (bytes32[] , int256) with (env e) => morphoMarketV1AdapterWrapperSummary(e, true, data, assets) ALL;
    function deallocate(bytes data, uint256 assets, bytes4, address) external returns (bytes32[] , int256) with (env e) => morphoMarketV1AdapterWrapperSummary(e, false, data, assets) ALL;

    function Utils.id(MorphoMarketV1Adapter.MarketParams) external returns (MorphoMarketV1Adapter.Id) envfree;
    function Utils.decodeMarketParams(bytes) external returns (MorphoMarketV1Adapter.MarketParams) envfree;
}

// Mimics the allocation in the vault corresponding to the function allocation of the MorphoMarketV1Adapter.
ghost mapping (MorphoMarketV1Adapter.Id => uint256) ghostAllocation;

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
    MorphoMarketV1Adapter.MarketParams marketParams = Utils.decodeMarketParams(data);
    MorphoMarketV1Adapter.Id marketId = Utils.id(marketParams);
    // Safe require because it is the same computation as in the implementation `(int256(allocation) + change).toUint256()`, except for the cast of the allocation to int256 which is guaranteed to be safe by the rule allocationIsInt256.
    ghostAllocation[marketId] = require_uint256(ghostAllocation[marketId] + change);
    return (ids, change);
}

// Prove that if a market has no allocation, it is not in the market ids list.
strong invariant marketIdsWithNoAllocationIsNotInMarketIds()
    forall MorphoMarketV1Adapter.Id marketId.
    forall uint256 i. i < currentContract.marketIds.length => ghostAllocation[marketId] == 0 => currentContract.marketIds[i] != marketId
{
    preserved {
        requireInvariant distinctMarketIdsInList();
    }
}

// Prove that marketIds contains distinct elements.
strong invariant distinctMarketIdsInList()
    forall uint256 i. forall uint256 j. i < j => j < currentContract.marketIds.length => currentContract.marketIds[j] != currentContract.marketIds[i]
{
    preserved {
        requireInvariant marketIdsWithNoAllocationIsNotInMarketIds();
    }
}
