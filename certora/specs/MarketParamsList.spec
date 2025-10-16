// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function allocation(MorphoMarketV1Adapter.MarketParams memory marketParams) internal returns (uint256) => ghostAllocation(marketParams);

    function MorphoBalancesLib.expectedSupplyAssets(address morpho, MorphoMarketV1Adapter.MarketParams memory marketParams, address user) internal returns (uint256) => summaryExpectedSupplyAssets(morpho, marketParams, user);
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

ghost mapping (address => mapping (address => mapping (address => mapping (address => mapping (uint256 => uint256))))) ghostAllocation;

definition ghostAllocation(MorphoMarketV1Adapter.MarketParams marketParams) returns uint256 = ghostAllocation[marketParams.loanToken][marketParams.collateralToken][marketParams.oracle][marketParams.irm][marketParams.lltv];

function summaryExpectedSupplyAssets(address morpho, MorphoMarketV1Adapter.MarketParams marketParams, address user) returns uint256 {
    uint256 result;
    require result <= max_int256(), "see allocationIsInt256";
    ghostAllocation[marketParams.loanToken][marketParams.collateralToken][marketParams.oracle][marketParams.irm][marketParams.lltv] = result;
    return result;
}

strong invariant noAllocationMarketParamsIsntInMarketParamsList()
    forall MorphoMarketV1Adapter.MarketParams marketParams. forall uint256 i. i < currentContract.marketParamsList.length => ghostAllocation(marketParams) == 0 => (
    currentContract.marketParamsList[i].loanToken != marketParams.loanToken ||
    currentContract.marketParamsList[i].collateralToken != marketParams.collateralToken ||
    currentContract.marketParamsList[i].oracle != marketParams.oracle ||
    currentContract.marketParamsList[i].irm != marketParams.irm ||
    currentContract.marketParamsList[i].lltv != marketParams.lltv
    )
{
    preserved {
        requireInvariant marketParamsListUnique();
    }
}

strong invariant marketParamsListUnique()
    forall uint256 i. forall uint256 j. (i < j && j < currentContract.marketParamsList.length) => (
    currentContract.marketParamsList[j].loanToken != currentContract.marketParamsList[i].loanToken ||
    currentContract.marketParamsList[j].collateralToken != currentContract.marketParamsList[i].collateralToken ||
    currentContract.marketParamsList[j].oracle != currentContract.marketParamsList[i].oracle ||
    currentContract.marketParamsList[j].irm != currentContract.marketParamsList[i].irm ||
    currentContract.marketParamsList[j].lltv != currentContract.marketParamsList[i].lltv
    )
{
    preserved {
        requireInvariant noAllocationMarketParamsIsntInMarketParamsList();
    }
}
