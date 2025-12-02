// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function allocation(MorphoMarketV1AdapterV2.MarketParams memory marketParams) internal returns (uint256) => summaryAllocation(marketParams);

    function expectedSupplyAssets(bytes32 marketId) internal returns (uint256) => summaryExpectedSupplyAssets(marketId);

    function Utils.id(MorphoMarketV1AdapterV2.MarketParams) external returns (MorphoMarketV1AdapterV2.Id) envfree;
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

// Mimics the allocation in the vault corresponding to the function allocation of the MorphoMarketV1AdapterV2.
ghost mapping (bytes32 => uint256) ghostAllocation;

function summaryAllocation(MorphoMarketV1AdapterV2.MarketParams marketParams) returns uint256 {
    return ghostAllocation[Utils.id(marketParams)];
}

function summaryExpectedSupplyAssets(bytes32 marketId) returns uint256 {
    uint256 newAllocation;
    require newAllocation <= max_int256(), "see allocationIsInt256";
    // Assumes that the allocation in the vault is newAllocation after allocate and deallocate.
    // Safe because it is a corollary of allocateChangesAllocationOfIds, deallocateChangesAllocationOfIds and allocationIsInt256.
    ghostAllocation[marketId] = newAllocation;
    return newAllocation;
}

// Prove that if a market has no allocation, it is not in the market ids list.
strong invariant marketIdsWithNoAllocationIsNotInMarketIds()
    forall bytes32 marketId.
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
