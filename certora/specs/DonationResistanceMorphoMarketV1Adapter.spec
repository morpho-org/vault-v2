// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function allocation(Morpho.MarketParams) external returns uint256 envfree;
    function marketParamsListLength() external returns uint256 envfree;
    function _.marketParamsListLength() external => DISPATCHER(true);
    function _.marketParamsList(uint256 i) external => DISPATCHER(true);

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect uint256;
    function _.borrowRateView(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect uint256;
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function Utils.isAllocated(address adapter, MorphoHarness.MarketParams) external returns bool envfree;
}

persistent ghost uint256 constantBorrowRate;

rule donationResistance(env e, MorphoHarness.MarketParams marketParams, uint256 donation) {
    assert currentContract.morpho == MorphoMarketV1;

    // Ensure that we check the conrete list exhaustively for an arbitrary lenght, the general case follows by induction on this rule.
    require (marketParamsListLength() < 5, "require that the list length is lesser than or equal the loop_iter setting");
    require !Utils.isAllocated(currentContract, marketParams);

    bytes data;
    require data.length == 0;

    uint256 realAssetsBefore = realAssets(e);

    MorphoMarketV1.supply(e, marketParams, donation, 0, currentContract, data);

    assert realAssetsBefore == realAssets(e);
}
