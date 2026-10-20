// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// Prove that the stored loss factor of each market is at most Midnight's.
strong invariant lossFactorBelowMidnightLossFactor()
    forall bytes32 marketId. currentContract.marketData[marketId].lossFactor <= ghostMidnightLossFactor[marketId];
