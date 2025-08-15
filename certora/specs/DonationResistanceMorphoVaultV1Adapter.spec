// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC4626Mock as ERC4626;
using MetaMorpho as MorphoVaultV1;
using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function _.deposit(uint256, address) external => DISPATCHER(true);
    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect uint256;
    function _.borrowRateView(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect uint256;
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns (uint256) => mulDivSummary(x,y,denominator);
    function Utils.isAllocated(address adapter, MorphoHarness.MarketParams) external returns bool envfree;
}

persistent ghost uint256 constantBorrowRate;

function mulDivSummary(uint256 x, uint256 y, uint256 denominator) returns uint256 {
    mathint result;
    if (denominator == 0) revert();
    result = x * y / denominator;
    if (result >= 2^256) revert();
    return assert_uint256(result);
}

rule donationResistance(env e, MorphoHarness.MarketParams marketParams, uint256 donation) {
    assert currentContract.morphoVaultV1 == MorphoVaultV1;
    assert MorphoVaultV1.MORPHO == MorphoMarketV1;

    require (MorphoVaultV1 != ERC4626, "assume these contracts to have different addresses");
    require (e.msg.sender != currentContract, "assume the sender is not the adapter");

    uint256 realAssetsBefore = realAssets(e);

    ERC4626.deposit(e, donation, currentContract);

    assert realAssetsBefore == realAssets(e);
}
