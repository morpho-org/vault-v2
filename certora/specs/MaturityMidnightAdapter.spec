// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    // A multicall is a sequence of the other calls, which are each checked.
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// Prove that a market with a non-zero stored maturity has a non-zero stored net credit.
strong invariant nonZeroMaturityHasNonZeroNetCredit()
    forall bytes32 marketId. currentContract.marketData[marketId].maturity != 0 => currentContract.marketData[marketId].netCredit != 0;

// Prove that a call changes a non-zero stored maturity only by resetting it to zero together with the stored net credit, as when the market is removed.
// This is a property of each call: across calls, a market can be removed and bought again, and in the adapter it then gets the same maturity because the market id commits to the maturity, which this model abstracts.
rule maturityImmutable(env e, method f, calldataarg args, bytes32 marketId) {
    requireInvariant nonZeroMaturityHasNonZeroNetCredit();
    uint48 maturityBefore = currentContract.marketData[marketId].maturity;

    f(e, args);

    uint48 maturityAfter = currentContract.marketData[marketId].maturity;
    assert maturityBefore != 0 && maturityAfter != maturityBefore => maturityAfter == 0 && currentContract.marketData[marketId].netCredit == 0;
}
