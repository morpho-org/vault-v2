// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function positions(bytes32 marketId) external returns (uint128, uint128) envfree;

    function newAllocation(bytes32 marketId) internal returns (uint256) => summaryNewAllocation(marketId);
}

function summaryNewAllocation(bytes32 marketId) returns (uint256) {
    uint256 newAllocation;
    require newAllocation < 2 ^ 128, "market v1 fits total supply assets on 128 bits";
    return newAllocation;
}

// Prove that if a market has no allocation, it is not in the market params list.
strong invariant marketParamsWithNoAllocationIsNotInMarketIds()
    forall bytes32 marketId. forall uint256 i. i < currentContract.marketIds.length => currentContract.positions[marketId].allocation == 0 => currentContract.marketIds[i] != marketId
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
