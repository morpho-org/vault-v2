// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// Prove that the stored loss factor of a market only changes to the last loss factor returned by Midnight for that market, or to zero when the market is removed.
// Since Midnight's loss factor never decreases, it follows that the stored loss factor is at most Midnight's.
rule lossFactorIsMidnightLossFactor(env e, method f, calldataarg args, bytes32 marketId) {
    uint128 lossFactorBefore = currentContract.marketData[marketId].lossFactor;

    f(e, args);

    uint128 lossFactorAfter = currentContract.marketData[marketId].lossFactor;
    assert lossFactorAfter != lossFactorBefore => lossFactorAfter == ghostLastMidnightLossFactor[marketId] || lossFactorAfter == 0;
}
