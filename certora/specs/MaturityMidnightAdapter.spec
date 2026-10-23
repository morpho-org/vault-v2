// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Uses the market list spec's model of the adapter's environment, and its invariants to tell whether a market is listed.
import "MarketIdsMidnightAdapter.spec";

methods {
    // The adapter's net credit in Midnight can be any value.
    function currentNetCredit(bytes32 marketId) internal returns (uint128) => NONDET;

    function _.liquidationLocked(bytes32, address) external => NONDET;

    // Calls into Midnight, resolved so that they don't havoc the adapter's state. Midnight's take calls back the adapter's onBuy or onSell, which this model drops: they are checked as entry points of their own.
    function _.take(MidnightAdapter.Offer, bytes, uint256, address, address, address, bytes) external => NONDET;
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => NONDET;
    function _.setConsumed(bytes32, uint128, address) external => NONDET;

    // The vault's calls into its adapters. Its calls back into this adapter (e.g. allocate from onBuy) are dropped by this model: they are checked as entry points of their own.
    function _.allocate(bytes, uint256, bytes4, address) external => NONDET;
    function _.deallocate(bytes, uint256, bytes4, address) external => NONDET;
}

definition isListed(bytes32 marketId) returns bool = currentContract.marketData[marketId].index < currentContract.marketIds.length && currentContract.marketIds[currentContract.marketData[marketId].index] == marketId;

// Prove that a market with a non-zero stored maturity has a non-zero stored net credit.
strong invariant nonZeroMaturityHasNonZeroNetCredit()
    forall bytes32 marketId. currentContract.marketData[marketId].maturity != 0 => currentContract.marketData[marketId].netCredit != 0;

// Whether a non-zero maturity of the market has been changed, other than by a reset to zero once the market is out of the list with a zero stored net credit, as when the market is removed.
persistent ghost mapping(bytes32 => bool) ghostInvalidMaturityWrite;

hook Sstore currentContract.marketData[KEY bytes32 marketId].maturity uint48 maturity (uint48 oldMaturity) {
    if (
        oldMaturity != 0
            && maturity != oldMaturity
            && !(maturity == 0
            && !isListed(marketId)
            && currentContract.marketData[marketId].netCredit == 0)
    ) {
        ghostInvalidMaturityWrite[marketId] = true;
    }
}

// Prove that a call changes a non-zero stored maturity only by resetting it to zero, once the market is out of the list with a zero stored net credit, as when the market is removed. Every write is checked, so the maturity is never changed in the middle of a call either.
// The net credit can be non-zero again at the end of the call: in this model, Midnight's net credit can be any value, so withdrawToVault can store a non-zero net credit after onBuy removed the market.
// This is a property of each call: across calls, a market can be removed and bought again, and in the adapter it then gets the same maturity because the market id commits to the maturity, which this model abstracts.
rule maturityImmutable(env e, method f, calldataarg args, bytes32 marketId) {
    requireInvariant marketIdsLengthBounded();
    requireInvariant marketIdsIndex();
    requireInvariant listedHasNonZeroNetCredit();
    requireInvariant nonZeroMaturityHasNonZeroNetCredit();
    require !ghostInvalidMaturityWrite[marketId], "no invalid maturity write yet in this call";
    uint48 maturityBefore = currentContract.marketData[marketId].maturity;

    f(e, args);

    uint48 maturityAfter = currentContract.marketData[marketId].maturity;
    assert !ghostInvalidMaturityWrite[marketId];
    assert maturityBefore != 0 => maturityAfter == maturityBefore || maturityAfter == 0;
}
