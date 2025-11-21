// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function MorphoMarketV1Adapter.positions(MorphoMarketV1Adapter.Id marketId) external returns (uint256, uint256) envfree;
    function MorphoBalancesLib.expectedSupplyAssets(address morpho, MorphoMarketV1Adapter.MarketParams memory marketParams, address user) internal returns (uint256) => summaryExpectedSupplyAssets(morpho, marketParams, user);
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

// // Prove that if a market has no allocation, it is not in the market params list.
// strong invariant marketParamsWithNoAllocationIsNotInMarketParamsList()
//     forall bytes32 marketId. forall uint256 i. i < currentContract.marketParamsList.length => allocation(marketId) == 0 => (
//         currentContract.marketParamsList[i].loanToken != loanToken ||
//         currentContract.marketParamsList[i].collateralToken != collateralToken ||
//         currentContract.marketParamsList[i].oracle != oracle ||
//         currentContract.marketParamsList[i].irm != irm ||
//         currentContract.marketParamsList[i].lltv != lltv
//     )
// {
//     preserved {
//         requireInvariant distinctMarketParamsInList();
//     }
// }

// // Prove that marketParamsList contains distinct elements.
// strong invariant distinctMarketParamsInList()
//     forall uint256 i. forall uint256 j. (i < j && j < currentContract.marketParamsList.length) => (
//         currentContract.marketParamsList[j].loanToken != currentContract.marketParamsList[i].loanToken ||
//         currentContract.marketParamsList[j].collateralToken != currentContract.marketParamsList[i].collateralToken ||
//         currentContract.marketParamsList[j].oracle != currentContract.marketParamsList[i].oracle ||
//         currentContract.marketParamsList[j].irm != currentContract.marketParamsList[i].irm ||
//         currentContract.marketParamsList[j].lltv != currentContract.marketParamsList[i].lltv
//     )
// {
//     preserved {
//         requireInvariant marketParamsWithNoAllocationIsNotInMarketParamsList();
//     }
// }
