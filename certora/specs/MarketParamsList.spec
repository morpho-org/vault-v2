// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function positions(MorphoMarketV1Adapter.Id marketId) external returns (uint128, uint128) envfree;
}

// Prove that if a market has no allocation, it is not in the market params list.
strong invariant marketParamsWithNoAllocationIsNotInMarketIds()
    forall MorphoMarketV1Adapter.Id marketId. forall uint256 i. i < currentContract.marketIds.length => currentContract.positions[marketId].allocation == 0 => currentContract.marketIds[i] != marketId.unwrap()
{
    preserved {
        requireInvariant distinctMarketIds();
    }
}

// Prove that marketIds contains distinct elements.
strong invariant distinctMarketIds()
    forall uint256 i. forall uint256 j. (i < j && j < currentContract.marketIds.length) => currentContract.marketIds[j] != currentContract.marketIds[i]
{
    preserved {
        requireInvariant marketParamsWithNoAllocationIsNotInMarketIds();
    }
}
