// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityMidnightAdapter.spec";

using Havoc as havocCallback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function MAX_MARKETS() external returns (uint256) envfree;

    // Same summary as in MarketIdsMidnightAdapter.spec, where it is explained.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // Midnight.withdraw does not reenter the adapter, assuming the loan token does not reenter.
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => HAVOC_ECF;

    // Midnight.take only calls back the offer's callback and the taker callback, the other calls being views or loan token transfers.
    function _.take(MidnightAdapter.Offer offer, bytes, uint256, address, address, address takerCallback, bytes) external => cvlTake(offer, takerCallback) expect(uint256, uint256);
    function _.havocAll() external => HAVOC_ALL;

    // The loan token and enter gate must not reenter the adapter.
    function _.transferFrom(address, address, uint256) external => HAVOC_ECF;
    function _.admit(address, address) external => HAVOC_ECF;
    function _.updatePositionView(MidnightAdapter.Market, bytes32 id, address user) external => cvlUpdatePositionView(id, user) expect(uint128, uint128, uint128);
}

// The adapter's net credit (credit minus pending fee) in each Midnight market.
persistent ghost mapping(bytes32 => uint128) ghostMidnightNetCredit {
    init_state axiom forall bytes32 marketId. ghostMidnightNetCredit[marketId] == 0;
}

// An arbitrary call if a callback is neither the adapter nor absent.
// Otherwise, the callbacks are the adapter's own: in take, the Midnight call is last, so they are checked as entry points; in forceDeallocate, onBuy only clears transient flags that neither these invariants nor the remaining code read.
function cvlTake(MidnightAdapter.Offer offer, address takerCallback) returns (uint256, uint256) {
    if (isArbitraryCallback(offer.callback) || isArbitraryCallback(takerCallback)) {
        env e;
        address dummy;
        havocCallback.callHavoc(e, dummy);
    }
    uint256 buyerAssets;
    uint256 sellerAssets;
    return (buyerAssets, sellerAssets);
}

definition isArbitraryCallback(address callback) returns bool = callback != 0 && callback != currentContract;

// Market list properties proved in MarketIdsMidnightAdapter.spec.
function requireMarketIdsInvariants() {
    require currentContract.marketIds.length <= MAX_MARKETS(), "see marketIdsLengthBounded in MarketIdsMidnightAdapter.spec";
    require forall uint256 i. i < currentContract.marketIds.length => currentContract.marketData[currentContract.marketIds[i]].index == i, "see marketIdsIndex in MarketIdsMidnightAdapter.spec";
}

// The adapter's net credit in Midnight can decrease at any time (sales, withdrawals, losses), so each read can return a lower value. It increases only when the adapter buys, which Midnight does before calling onBuy, checked as an entry point.
function cvlUpdatePositionView(bytes32 id, address user) returns (uint128, uint128, uint128) {
    uint128 credit;
    uint128 pendingFee;
    uint128 accruedFee;
    if (user == currentContract) {
        require credit - pendingFee <= ghostMidnightNetCredit[id], "Midnight net credit only increases in buys";
        if (credit >= pendingFee) ghostMidnightNetCredit[id] = assert_uint128(credit - pendingFee);
    }
    return (credit, pendingFee, accruedFee);
}

// Midnight credits the bought units to the adapter before calling onBuy.
function increaseMidnightNetCredit(bytes32 marketId) {
    uint128 newNetCredit;
    ghostMidnightNetCredit[marketId] = newNetCredit;
}

// Prove that stored net credit bounds Midnight net credit unless the market was force removed.
strong invariant midnightNetCreditBelowStoredNetCredit()
    forall bytes32 marketId. !currentContract.marketData[marketId].forceRemoved => ghostMidnightNetCredit[marketId] <= currentContract.marketData[marketId].netCredit
    {
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            // Midnight credits the adapter before calling onBuy, including when the adapter is the maker.
            // Exception: forceDeallocate sells the adapter's position, so the position does not increase.  onBuy is called only to clear enterGate bypass
            if (!currentContract.inForceDeallocate) {
                increaseMidnightNetCredit(marketId);
            }
        }
    }

// Prove that a market with a non-zero stored net credit is in the list.
// This relies on midnightNetCreditBelowStoredNetCredit: onSell and deallocate store the adapter's net credit in Midnight without listing the market.
strong invariant nonZeroNetCreditIsListed()
    forall bytes32 marketId. currentContract.marketData[marketId].netCredit != 0 => currentContract.marketData[marketId].index < currentContract.marketIds.length && currentContract.marketIds[currentContract.marketData[marketId].index] == marketId
    {
        preserved {
            requireInvariant midnightNetCreditBelowStoredNetCredit();
            requireMarketIdsInvariants();
        }
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            requireInvariant midnightNetCreditBelowStoredNetCredit();
            requireMarketIdsInvariants();
        
            // forceDeallocate sells the adapter's position, so the position does not increase.  onBuy is called only to clear enterGate bypass
            if (!currentContract.inForceDeallocate) {
                increaseMidnightNetCredit(marketId);
            }
        }
    }
