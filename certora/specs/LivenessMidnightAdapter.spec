// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

using Midnight as Midnight;

methods {
    function inProgressBuyBoughtNetCredit() external returns (uint256) envfree;

    // The lock is in transient storage at a hashed slot, which CVL can't constrain directly.
    function Midnight.liquidationLocked(bytes32 id, address user) external returns (bool) => liquidationLockedGhost(id, user);
}

ghost liquidationLockedGhost(bytes32, address) returns bool;

// Check that realAssets doesn't revert outside of a buy or a sale, assuming Midnight's invariants on the adapter's positions.
// With optimistic_loop and loop_iter 2, this rule only checks lists of up to 2 markets.
// Each iteration leaves storage unchanged and adds at most max_uint128 to assets: netCredit fits in uint128 under the assumptions below, and discounting cannot increase it.
// For longer lists, marketIdsLengthBounded in MarketIdsMidnightAdapter.spec bounds the length to MAX_MARKETS = 250, so assets < 2^136 and cannot overflow.
rule livenessRealAssets(env e) {
    require e.msg.value == 0, "realAssets is not payable";
    require inProgressBuyBoughtNetCredit() == 0, "no buy in progress, see onBuy";
    require forall bytes32 id. !liquidationLockedGhost(id, currentContract), "no sale in progress, Midnight sets this lock only during a sale";
    require forall bytes32 id. Midnight.position[id][currentContract].pendingFee <= Midnight.position[id][currentContract].credit, "see pendingContinuousFeeBoundedByCredit in Midnight's Midnight.spec";
    require forall bytes32 id. Midnight.position[id][currentContract].lastLossFactor <= Midnight.marketState[id].lossFactor, "see lastLossFactorLeqMarketLossFactor in Midnight's Midnight.spec";

    realAssets@withrevert(e);

    assert !lastReverted;
}
