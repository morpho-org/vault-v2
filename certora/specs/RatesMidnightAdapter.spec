// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Each rule assumes that a guardrail is not met, and checks that the call reverts.
methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function maxTtm() external returns (uint32) envfree;
    function minNetBuyRate() external returns (uint64) envfree;
    function maxNetSellRate() external returns (uint64) envfree;
    function noSalesWithShortfall() external returns (bool) envfree;

    // Over-approximation that keeps the adapter's storage, which the guardrails read after this call.
    function currentNetCredit(bytes32 marketId) internal returns (uint128) => NONDET;
}

definition WAD() returns mathint = 10 ^ 18;

// Check that a buy reverts in a forceSellable market.
rule buyRevertsInForceSellableMarket(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) {
    require currentContract.marketData[marketId].forceSellable;

    onBuy@withrevert(e, marketId, market, paidAssets, boughtCredit, buyPendingFeeIncrease, buyer, callbackData);

    assert lastReverted;
}

// Check that a buy reverts if the market is matured or its time to maturity is above maxTtm.
rule buyRevertsIfTtmOutOfBounds(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) {
    mathint ttm = market.maturity - e.block.timestamp;
    require ttm <= 0 || ttm > maxTtm();

    onBuy@withrevert(e, marketId, market, paidAssets, boughtCredit, buyPendingFeeIncrease, buyer, callbackData);

    assert lastReverted;
}

// Check that a buy reverts if its net rate is below minNetBuyRate.
rule buyRevertsIfNetRateTooLow(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) {
    mathint ttm = market.maturity - e.block.timestamp;
    mathint boughtNetCredit = boughtCredit - buyPendingFeeIncrease;

    // In real numbers: (boughtNetCredit - paidAssets) / paidAssets < minNetBuyRate * ttm / WAD, written without division.
    require (boughtNetCredit - paidAssets) * WAD() < minNetBuyRate() * ttm * paidAssets;

    onBuy@withrevert(e, marketId, market, paidAssets, boughtCredit, buyPendingFeeIncrease, buyer, callbackData);

    assert lastReverted;
}

// Check that a sale in a forceSellable market reverts if its price is below minForceSellPrice.
rule forceSaleRevertsIfPriceTooLow(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 sellerAssets, uint256 soldCredit, uint256 sellPendingFeeDecrease, address seller, address receiver, bytes callbackData) {
    mathint soldNetCredit = soldCredit - sellPendingFeeDecrease;
    require currentContract.marketData[marketId].forceSellable;
    require sellerAssets * WAD() < soldNetCredit * currentContract.marketData[marketId].minForceSellPrice;

    onSell@withrevert(e, marketId, market, sellerAssets, soldCredit, sellPendingFeeDecrease, seller, receiver, callbackData);

    assert lastReverted;
}

// Check that a sale in a market that is not forceSellable reverts if its net rate is above maxNetSellRate.
rule saleRevertsIfNetRateTooHigh(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 sellerAssets, uint256 soldCredit, uint256 sellPendingFeeDecrease, address seller, address receiver, bytes callbackData) {
    mathint ttm = market.maturity > e.block.timestamp ? market.maturity - e.block.timestamp : 0;
    mathint soldNetCredit = soldCredit - sellPendingFeeDecrease;
    require !currentContract.marketData[marketId].forceSellable;
    require sellerAssets * (WAD() + maxNetSellRate() * ttm) < soldNetCredit * WAD();

    onSell@withrevert(e, marketId, market, sellerAssets, soldCredit, sellPendingFeeDecrease, seller, receiver, callbackData);

    assert lastReverted;
}

// Check that, when noSalesWithShortfall is set, a sale in a market that is not forceSellable reverts if it has a shortfall.
rule saleRevertsIfShortfallDisabled(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 sellerAssets, uint256 soldCredit, uint256 sellPendingFeeDecrease, address seller, address receiver, bytes callbackData) {
    mathint ttm = market.maturity > e.block.timestamp ? market.maturity - e.block.timestamp : 0;
    mathint soldNetCredit = soldCredit - sellPendingFeeDecrease;
    require !currentContract.marketData[marketId].forceSellable;
    require noSalesWithShortfall();
    require sellerAssets * (WAD() + currentContract.marketData[marketId].netRate * ttm) < soldNetCredit * WAD();

    onSell@withrevert(e, marketId, market, sellerAssets, soldCredit, sellPendingFeeDecrease, seller, receiver, callbackData);

    assert lastReverted;
}
