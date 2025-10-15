// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function Util.libId(MorphoMarketV1Adapter.MarketParams) external returns MorphoMarketV1Adapter.Id envfree;

    function allocation(MorphoMarketV1Adapter.MarketParams memory marketParams) internal returns (uint256) => ghostAllocation(marketParams);

    function MorphoBalancesLib.expectedSupplyAssets(address morpho, MorphoMarketV1Adapter.MarketParams memory marketParams, address user) internal returns (uint256) => summaryExpectedSupplyAssets(morpho, marketParams, user);
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

ghost mapping (MorphoMarketV1Adapter.Id => uint256) ghostAllocation;

function ghostAllocation(MorphoMarketV1Adapter.MarketParams marketParams) returns uint256 {
    return ghostAllocation[Util.libId(marketParams)];
}

function summaryExpectedSupplyAssets(address morpho, MorphoMarketV1Adapter.MarketParams marketParams, address user) returns uint256 {
    uint256 result;
    require result <= max_int256(), "see allocationIsInt256";
    ghostAllocation[Util.libId(marketParams)] = result;
    return result;
}

strong invariant noAllocationMarketParamsIsntInMarketParamsList()
    forall MorphoMarketV1Adapter.MarketParams marketParams. forall uint256 i. i < currentContract.marketParamsList.length => ghostAllocation(marketParams) == 0 => currentContract.marketParamsList[i] != marketParams
{ preserved {
        requireInvariant marketParamsListUnique();
    }
}

strong invariant marketParamsListUnique()
    forall uint256 i. forall uint256 j. (i < j && j < currentContract.marketParamsList.length) => currentContract.marketParamsList[j] != currentContract.marketParamsList[i]
{
    preserved {
        requireInvariant noAllocationMarketParamsIsntInMarketParamsList();
    }
}
