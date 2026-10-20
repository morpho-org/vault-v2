// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// Prove that a market with a non-zero stored maturity has a non-zero stored net credit.
strong invariant nonZeroMaturityHasNonZeroNetCredit()
    forall bytes32 marketId. currentContract.marketData[marketId].maturity != 0 => currentContract.marketData[marketId].netCredit != 0;

// Prove that a non-zero stored maturity can only be reset to zero, which happens when the market is removed.
rule maturityImmutable(env e, method f, calldataarg args, bytes32 marketId) {
    requireInvariant nonZeroMaturityHasNonZeroNetCredit();
    uint48 maturityBefore = currentContract.marketData[marketId].maturity;

    f(e, args);

    uint48 maturityAfter = currentContract.marketData[marketId].maturity;
    assert maturityBefore != 0 => maturityAfter == maturityBefore || maturityAfter == 0;
}
