// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

using Midnight as Midnight;

methods {
    function inProgressBuyBoughtNetCredit() external returns (uint256) envfree;

    // Assume that no sale of the adapter's credit is in progress: Midnight sets this transient lock only during a sale.
    function Midnight.liquidationLocked(bytes32, address) external returns (bool) => ALWAYS(false);
}

// Check that realAssets doesn't revert outside of a buy or a sale, assuming Midnight's invariants on the adapter's positions.
rule livenessRealAssets(env e) {
    require e.msg.value == 0, "realAssets is not payable";
    require inProgressBuyBoughtNetCredit() == 0, "no buy in progress, see onBuy";
    require forall bytes32 id. Midnight.position[id][currentContract].pendingFee <= Midnight.position[id][currentContract].credit, "see pendingContinuousFeeBoundedByCredit in Midnight's Midnight.spec";
    require forall bytes32 id. Midnight.position[id][currentContract].lastLossFactor <= Midnight.marketState[id].lossFactor, "see lastLossFactorLeqMarketLossFactor in Midnight's Midnight.spec";

    realAssets@withrevert(e);

    assert !lastReverted;
}
