// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// Prove that a call changes the stored loss factor of a market only to a loss factor that Midnight returned for that market during the call, or to zero when the market is removed.
// This does not prove that the stored loss factor is at most Midnight's current one, which also needs Midnight's loss factor to never decrease.
rule lossFactorIsMidnightLossFactor(env e, method f, calldataarg args, bytes32 marketId) {
    require forall uint128 lossFactor. !ghostMidnightLossFactorReturned[marketId][lossFactor];
    uint128 lossFactorBefore = currentContract.marketData[marketId].lossFactor;

    f(e, args);

    uint128 lossFactorAfter = currentContract.marketData[marketId].lossFactor;
    assert lossFactorAfter != lossFactorBefore => ghostMidnightLossFactorReturned[marketId][lossFactorAfter] || lossFactorAfter == 0;
}
