// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

using Havoc as havocCallback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function MAX_MARKETS() external returns (uint256) envfree;

    // Same summaries as in MarketIdsMidnightAdapter.spec, where they are explained.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // Midnight.withdraw does not reenter the adapter, assuming the loan token does not reenter.
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => HAVOC_ECF;

    // Midnight.take only calls back the offer's callback and the taker callback, the other calls being views or loan token transfers.
    function _.take(MidnightAdapter.Offer offer, bytes, uint256, address taker, address, address takerCallback, bytes) external => cvlTake(offer, taker, takerCallback) expect(uint256, uint256);
    function _.havocAll() external => HAVOC_ALL;
    function _.setIsAuthorized(address authorized, bool newIsAuthorized, address) external => recordAuthorization(calledContract, executingContract, authorized, newIsAuthorized) expect void;

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
function cvlTake(MidnightAdapter.Offer offer, address taker, address takerCallback) returns (uint256, uint256) {
    require offer.maker != taker, "Midnight's take reverts with SelfTake when maker == taker";
    require offer.maker == currentContract => currentContract.inForceDeallocate || offer.callback == currentContract, "Midnight requires an authorized maker ratifier; adapterOnlyAuthorizesItself checks its authorizations, and isRatifiedRequiresAdapterCallback checks its callback outside forceDeallocate";
    address buyer = offer.buy ? offer.maker : taker;
    address buyerCallback = offer.buy ? offer.callback : takerCallback;

    // If the buyer-side callback is the adapter, Midnight credits it before onBuy, checked as an entry point (netCreditIncreaseCallsOnBuy, midnight PR #1252).
    // The invariants exclude other callbacks: take passes itself, isRatified checks its offers, and forceDeallocate makes it the seller of a sell offer.
    if (buyer == currentContract && buyerCallback != currentContract) {
        bytes32 marketId;
        increaseMidnightNetCredit(marketId);
    }
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

function arbitraryIds() returns bytes32[] {
    bytes32[] idsArray;
    return idsArray;
}

function arbitraryAllocations(uint256 length) returns uint256[] {
    uint256[] allocations;
    require allocations.length == length, "durationAllocations returns length allocations";
    return allocations;
}

// Market list properties proved in MarketIdsMidnightAdapter.spec.
function requireMarketIdsInvariants() {
    require currentContract.marketIds.length <= MAX_MARKETS(), "see marketIdsLengthBounded in MarketIdsMidnightAdapter.spec";
    require forall uint256 i. i < currentContract.marketIds.length => currentContract.marketData[currentContract.marketIds[i]].index == i, "see marketIdsIndex in MarketIdsMidnightAdapter.spec";
}

// Net credit can decrease at any read (sales, withdrawals, losses). Increases with the adapter as buyer-side callback precede onBuy, checked as an entry point; cvlTake models other callbacks.
function cvlUpdatePositionView(bytes32 id, address user) returns (uint128, uint128, uint128) {
    uint128 credit;
    uint128 pendingFee;
    uint128 accruedFee;
    if (user == currentContract) {
        require credit - pendingFee <= ghostMidnightNetCredit[id], "Midnight net credit increases are modeled in onBuy and cvlTake";
        if (credit >= pendingFee) ghostMidnightNetCredit[id] = assert_uint128(credit - pendingFee);
    }
    return (credit, pendingFee, accruedFee);
}

// Model Midnight crediting the adapter, before onBuy if it is the buyer-side callback.
function increaseMidnightNetCredit(bytes32 marketId) {
    uint128 newNetCredit;
    ghostMidnightNetCredit[marketId] = newNetCredit;
}

definition midnightNetCreditBounded() returns bool = forall bytes32 marketId. !currentContract.marketData[marketId].forceRemoved => ghostMidnightNetCredit[marketId] <= currentContract.marketData[marketId].netCredit;

// Prove that stored net credit bounds Midnight net credit unless the market was force removed.
strong invariant midnightNetCreditBelowStoredNetCredit()
    midnightNetCreditBounded()
    {
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            // With the adapter as buyer-side callback, Midnight credits it before onBuy, including as maker.
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
        
            // With the adapter as buyer-side callback, Midnight credits it before onBuy, except in forceDeallocate where it sells.
            if (!currentContract.inForceDeallocate) {
                increaseMidnightNetCredit(marketId);
            }
        }
    }

// Whether the method being checked may increase stored net credit: onBuy, unless called back from forceDeallocate.
persistent ghost bool netCreditIncreaseAllowed;

// Whether stored net credit increased in a method that may not increase it.
persistent ghost bool netCreditIncreasedOutsideBuy {
    init_state axiom !netCreditIncreasedOutsideBuy;
}

hook Sstore currentContract.marketData[KEY bytes32 marketId].netCredit uint128 newNetCredit (uint128 oldNetCredit) {
    if (newNetCredit > oldNetCredit && !netCreditIncreaseAllowed) netCreditIncreasedOutsideBuy = true;
}

// Prove that stored net credit increases only in onBuy, and not when onBuy is called back from forceDeallocate.
// It includes midnightNetCreditBelowStoredNetCredit so that it also holds after the arbitrary calls of strong invariants: other methods store the adapter's net credit in Midnight, which is then at most the stored net credit.
strong invariant storedNetCreditIncreasesOnlyInBuy()
    !netCreditIncreasedOutsideBuy && midnightNetCreditBounded()
    {
        preserved {
            netCreditIncreaseAllowed = false;
        }
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            // With the adapter as buyer-side callback, Midnight credits it before onBuy, except in forceDeallocate where it sells.
            netCreditIncreaseAllowed = !currentContract.inForceDeallocate;
            if (!currentContract.inForceDeallocate) {
                increaseMidnightNetCredit(marketId);
            }
        }
    }

rule isRatifiedRequiresAdapterCallback(env e, MidnightAdapter.Offer offer, bytes ratifierData, address taker) {
    require !currentContract.inForceDeallocate, "forceDeallocate bypasses ratification checks";
    isRatified(e, offer, ratifierData, taker);
    assert offer.maker == currentContract && offer.callback == currentContract;
}

// Persistent so arbitrary callbacks cannot erase the adapter's authorization calls.
persistent ghost bool authorizedAnotherAccount {
    init_state axiom !authorizedAnotherAccount;
}

function recordAuthorization(address target, address caller, address authorized, bool newIsAuthorized) {
    if (
        target == currentContract.midnight
            && caller == currentContract
            && newIsAuthorized
            && authorized != currentContract
    ) {
        authorizedAnotherAccount = true;
    }
}

// Check the constructor and every adapter method, including reentrant calls.
strong invariant adapterOnlyAuthorizesItself()
    !authorizedAnotherAccount;
