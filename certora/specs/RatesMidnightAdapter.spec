// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    function maxTtm() external returns (uint32) envfree;
    function minNetBuyRate() external returns (uint64) envfree;
    function maxNetSellRate() external returns (uint64) envfree;
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

definition WAD() returns mathint = 10 ^ 18;

// Prove that a buy succeeds only if the market's time to maturity is at most maxTtm, and the net rate of the buy is at least minNetBuyRate.
rule buyRespectsGuardrails(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) {
    mathint maxTtmBefore = maxTtm();
    mathint minNetBuyRateBefore = minNetBuyRate();

    onBuy(e, marketId, market, paidAssets, boughtCredit, buyPendingFeeIncrease, buyer, callbackData);

    mathint ttm = market.maturity - e.block.timestamp;
    mathint boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
    assert ttm > 0 && ttm <= maxTtmBefore;
    assert (boughtNetCredit - paidAssets) * WAD() >= minNetBuyRateBefore * ttm * paidAssets;
}

// Prove that a sale succeeds only if its price is at least minForceSellPrice in forceSellable markets, and its net rate is at most maxNetSellRate in other markets.
rule sellRespectsGuardrails(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 sellerAssets, uint256 soldCredit, uint256 sellPendingFeeDecrease, address seller, address receiver, bytes callbackData) {
    bool forceSellable = currentContract.marketData[marketId].forceSellable;
    mathint minForceSellPrice = currentContract.marketData[marketId].minForceSellPrice;
    mathint maxNetSellRateBefore = maxNetSellRate();

    onSell(e, marketId, market, sellerAssets, soldCredit, sellPendingFeeDecrease, seller, receiver, callbackData);

    mathint ttm = market.maturity > e.block.timestamp ? market.maturity - e.block.timestamp : 0;
    mathint soldNetCredit = soldCredit - sellPendingFeeDecrease;
    assert forceSellable => sellerAssets * WAD() >= soldNetCredit * minForceSellPrice;
    assert !forceSellable => sellerAssets * (WAD() + maxNetSellRateBefore * ttm) >= soldNetCredit * WAD();
}
