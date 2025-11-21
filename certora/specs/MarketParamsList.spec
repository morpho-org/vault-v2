// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function positions(MorphoMarketV1Adapter.Id marketId) external returns (uint128, uint128) envfree;
}

function allocation(MorphoMarketV1Adapter.Id marketId) returns (uint256) {
    uint128 supplyShares;
    uint128 allocation;
    (supplyShares, allocation) = positions(marketId);
    return allocation;
}

// Prove that if a market has no allocation, it is not in the market params list.
strong invariant marketParamsWithNoAllocationIsNotInMarketParamsList()
    forall bytes32 marketId. forall uint256 i. i < currentContract.marketIds.length => allocation(marketId) == 0 => currentContract.marketIds[i] != marketId
{
    preserved {
        requireInvariant distinctMarketParamsInList();
    }
}

// Prove that marketParamsList contains distinct elements.
strong invariant distinctMarketParamsInList()
    forall uint256 i. forall uint256 j. (i < j && j < currentContract.marketIds.length) => currentContract.marketIds[j] != currentContract.marketIds[i]
{
    preserved {
        requireInvariant marketParamsWithNoAllocationIsNotInMarketParamsList();
    }
}
