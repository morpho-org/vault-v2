// SPDX-License-Identifier: GPL-2.0-or-later

using Util as Util;

methods {
    function allocation(MorphoMarketV1Adapter.MarketParams memory marketParams) internal returns (uint256) => ghostAllocation[marketParams.loanToken][marketParams.collateralToken][marketParams.oracle][marketParams.irm][marketParams.lltv];

    function MorphoBalancesLib.expectedSupplyAssets(address morpho, MorphoMarketV1Adapter.MarketParams memory marketParams, address user) internal returns (uint256) => summaryExpectedSupplyAssets(morpho, marketParams, user);
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

// Mimics the allocation in the vault corresponding to the function allocation of the MorphoMarketV1Adapter.
ghost mapping (address => mapping (address => mapping (address => mapping (address => mapping (uint256 => uint256))))) ghostAllocation;

function summaryExpectedSupplyAssets(address morpho, MorphoMarketV1Adapter.MarketParams marketParams, address user) returns uint256 {
    uint256 newAllocation;
    require newAllocation <= max_int256(), "see allocationIsInt256";
    // Assumes that the allocation in the vault is newAllocation after allocate and deallocate.
    // Safe because it is a corollary of allocateChangesAllocationOfIds, deallocateChangesAllocationOfIds and allocationIsInt256.
    ghostAllocation[marketParams.loanToken][marketParams.collateralToken][marketParams.oracle][marketParams.irm][marketParams.lltv] = newAllocation;
    return newAllocation;
}

// Prove that if a market has no allocation, it is not in the market params list.
strong invariant marketParamsWithNoAllocationIsNotInMarketParamsList()
    forall address loanToken. forall address collateralToken. forall address oracle. forall address irm. forall uint256 lltv.
    forall uint256 i. i < currentContract.marketParamsList.length => ghostAllocation[loanToken][collateralToken][oracle][irm][lltv] == 0 => (
        currentContract.marketParamsList[i].loanToken != loanToken ||
        currentContract.marketParamsList[i].collateralToken != collateralToken ||
        currentContract.marketParamsList[i].oracle != oracle ||
        currentContract.marketParamsList[i].irm != irm ||
        currentContract.marketParamsList[i].lltv != lltv
    )
{
    preserved {
        requireInvariant distinctMarketParamsInList();
    }
}

// Prove that marketParamsList contains distinct elements.
strong invariant distinctMarketParamsInList()
    forall uint256 i. forall uint256 j. (i < j && j < currentContract.marketParamsList.length) => (
        currentContract.marketParamsList[j].loanToken != currentContract.marketParamsList[i].loanToken ||
        currentContract.marketParamsList[j].collateralToken != currentContract.marketParamsList[i].collateralToken ||
        currentContract.marketParamsList[j].oracle != currentContract.marketParamsList[i].oracle ||
        currentContract.marketParamsList[j].irm != currentContract.marketParamsList[i].irm ||
        currentContract.marketParamsList[j].lltv != currentContract.marketParamsList[i].lltv
    )
{
    preserved {
        requireInvariant marketParamsWithNoAllocationIsNotInMarketParamsList();
    }
}
