// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoHarness as Morpho;
using Utils as Utils;

methods {
    function _.extSloads(bytes32[]) external => NONDET DELETE;
    function _.multicall(bytes[] data) external => HAVOC_ALL DELETE;
    function _.supplyShares(address, Morpho.Id id, address user) internal => summarySupplyShares(id, user) expect uint256;

    function Morpho.supplyShares(Morpho.Id, address) external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketParamsListLength() external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketParamsList(uint256) external returns (address, address, address, address, uint256) envfree;
    function Utils.decodeMarketParams(bytes data) external returns (Morpho.MarketParams memory) envfree;

    function _.deallocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);

    // Todo: remove once it's linked to ERC20Mock.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => ghostBorrowRate expect uint256;
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => ghostBorrowRate expect uint256;

    function _.market(Morpho.Id) external => DISPATCHER(true);
}

persistent ghost uint256 ghostBorrowRate;

function summarySupplyShares(Morpho.Id id, address user) returns uint256 {
    return Morpho.supplyShares(id, user);
}

rule canRemoveMarket(env e, bytes data) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    require Morpho.feeRecipient != MorphoMarketV1Adapter, "sane assumption to simplify the amount of asset to remove";
    uint256 assets = Utils.expectedSupplyAssets(e, Morpho, marketParams, MorphoMarketV1Adapter);

    uint256 marketParamsListLength = MorphoMarketV1Adapter.marketParamsListLength();
    require forall uint256 i. forall uint256 j. (i < j && j < marketParamsListLength) => (
        MorphoMarketV1Adapter.marketParamsList[i].loanToken != MorphoMarketV1Adapter.marketParamsList[j].loanToken ||
        MorphoMarketV1Adapter.marketParamsList[i].collateralToken != MorphoMarketV1Adapter.marketParamsList[j].collateralToken ||
        MorphoMarketV1Adapter.marketParamsList[i].oracle != MorphoMarketV1Adapter.marketParamsList[j].oracle ||
        MorphoMarketV1Adapter.marketParamsList[i].irm != MorphoMarketV1Adapter.marketParamsList[j].irm ||
        MorphoMarketV1Adapter.marketParamsList[i].lltv != MorphoMarketV1Adapter.marketParamsList[j].lltv
    ), "see distinctMarketParamsInList";

    // Could also check that the deallocate call doesn't revert.
    deallocate(e, MorphoMarketV1Adapter, data, assets);

    require Morpho.supplyShares(marketId, MorphoMarketV1Adapter) == 0, "see deallocatingExpectedSupplyAssetsRemovesAllShares";

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

rule deallocatingExpectedSupplyAssetsRemovesAllShares(env e, bytes data) {
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    require Morpho.feeRecipient != MorphoMarketV1Adapter, "sane assumption to simplify the amount of asset to remove";
    uint256 assets = Utils.expectedSupplyAssets(e, Morpho, marketParams, MorphoMarketV1Adapter);

    // Could also check that the deallocate call doesn't revert.
    deallocate(e, MorphoMarketV1Adapter, data, assets);

    assert Morpho.supplyShares(marketId, MorphoMarketV1Adapter) == 0;
}
