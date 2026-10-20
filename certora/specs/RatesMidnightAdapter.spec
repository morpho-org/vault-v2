// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    function maxTtm() external returns (uint32) envfree;
    function minNetRate() external returns (uint64) envfree;
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// Prove that a stored net rate is only changed to a rate of at least minNetRate, or reset with the market's net credit.
rule netRateAboveMinNetRate(env e, method f, calldataarg args, bytes32 marketId) {
    uint64 netRateBefore = currentContract.marketData[marketId].netRate;

    f(e, args);

    uint64 netRateAfter = currentContract.marketData[marketId].netRate;
    assert netRateAfter != netRateBefore => netRateAfter >= minNetRate() || currentContract.marketData[marketId].netCredit == 0;
}

// Prove that the adapter only buys markets whose time to maturity is at most maxTtm.
rule buyTtmBelowMaxTtm(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) {
    uint32 maxTtmBefore = maxTtm();

    onBuy(e, marketId, market, paidAssets, boughtCredit, buyPendingFeeIncrease, buyer, callbackData);

    assert e.block.timestamp < market.maturity && market.maturity - e.block.timestamp <= maxTtmBefore;
}
