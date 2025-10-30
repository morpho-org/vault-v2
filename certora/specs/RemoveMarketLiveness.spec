// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoHarness as Morpho;
using Utils as Utils;

methods {
    function _.extSloads(bytes32[]) external => NONDET DELETE;
    function _.multicall(bytes[] data) external => HAVOC_ALL DELETE;
    function _.supplyShares(address, VaultV2.Id id, address user) internal => summarySupplyShares(id, user) expect uint256;

    function Morpho.supplyShares(VaultV2.Id, address) external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketParamsListLength() external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketParamsList(uint256) external returns (address, address, address, address, uint256) envfree;
    function Utils.decodeMarketParams(bytes data) external returns (VaultV2.MarketParams memory) envfree;

    function _.deallocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);
}

function summarySupplyShares(VaultV2.Id id, address user) returns uint256 {
    return Morpho.supplyShares(id, user);
}

ghost uint256 ghostMarketParamsListLength;
ghost mapping (uint256 => address) ghostLoanToken;
ghost mapping (uint256 => address) ghostCollateralToken;
ghost mapping (uint256 => address) ghostOracle;
ghost mapping (uint256 => address) ghostIrm;
ghost mapping (uint256 => uint256) ghostLltv;

hook Sload uint256 marketParamsListLength MorphoMarketV1Adapter.marketParamsList.(offset 0) {
    ghostMarketParamsListLength = marketParamsListLength;
}

hook Sstore MorphoMarketV1Adapter.marketParamsList.(offset 0) uint256 newMarketParamsListLength (uint256 oldMarketParamsListLength) {
    ghostMarketParamsListLength = newMarketParamsListLength;
}

hook Sload address loanToken MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].loanToken {
    ghostLoanToken[i] = loanToken;
}

hook Sstore MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].loanToken address newLoanToken (address oldLoanToken) {
    ghostLoanToken[i] = newLoanToken;
}

hook Sload address collateralToken MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].collateralToken {
    ghostCollateralToken[i] = collateralToken;
}

hook Sstore MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].collateralToken address newCollateralToken (address oldCollateralToken) {
    ghostCollateralToken[i] = newCollateralToken;
}

hook Sload address oracle MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].oracle {
    ghostOracle[i] = oracle;
}

hook Sstore MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].oracle address newOracle (address oldOracle) {
    ghostOracle[i] = newOracle;
}

hook Sload address irm MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].irm {
    ghostIrm[i] = irm;
}

hook Sstore MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].irm address newIrm (address oldIrm) {
    ghostIrm[i] = newIrm;
}

hook Sload uint256 lltv MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].lltv {
    ghostLltv[i] = lltv;
}

hook Sstore MorphoMarketV1Adapter.marketParamsList[INDEX uint256 i].lltv uint256 newLltv (uint256 oldLltv) {
    ghostLltv[i] = newLltv;
}

rule canRemoveMarket(env e, bytes data) {
    VaultV2.MarketParams marketParams = Utils.decodeMarketParams(data);
    uint256 assets = Utils.expectedSupplyAssets(e, Morpho, marketParams, MorphoMarketV1Adapter);

    require forall uint256 i. forall uint256 j. (i < j && j < ghostMarketParamsListLength) => (
        ghostLoanToken[i] != ghostLoanToken[j] ||
        ghostCollateralToken[i] != ghostCollateralToken[j] ||
        ghostOracle[i] != ghostOracle[j] ||
        ghostIrm[i] != ghostIrm[j] ||
        ghostLltv[i] != ghostLltv[j]
    ), "see distinctMarketParamsInList";

    // Could also check that the deallocate call doesn't revert.
    deallocate(e, MorphoMarketV1Adapter, data, assets);

    uint256 i;
    // Is this needed ?
    require i < MorphoMarketV1Adapter.marketParamsListLength();
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
    (loanToken, collateralToken, oracle, irm, lltv) = MorphoMarketV1Adapter.marketParamsList(i);
    assert (
        loanToken != marketParams.loanToken ||
        collateralToken != marketParams.collateralToken ||
        oracle != marketParams.oracle ||
        irm != marketParams.irm ||
        lltv != marketParams.lltv
    );
}
