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

    // Midnight.take is replaced by cvlTake, a model that follows Midnight's code.
    function _.take(MidnightAdapter.Offer offer, bytes, uint256 units, address taker, address, address takerCallback, bytes) external => cvlTake(offer, units, taker, takerCallback) expect(uint256, uint256);
    function _.havocAll() external => HAVOC_ALL;

    // The loan token and enter gate must not reenter the adapter.
    function _.transferFrom(address, address, uint256) external => HAVOC_ECF;
    function _.admit(address, address) external => HAVOC_ECF;
    function _.unadmit() external => HAVOC_ECF;
    function _.updatePositionView(MidnightAdapter.Market, bytes32 id, address user) external => cvlUpdatePositionView(id, user) expect(uint128, uint128, uint128);
}

// The adapter's net credit (credit minus pending fee) in each Midnight market.
ghost mapping(bytes32 => uint128) ghostMidnightNetCredit {
    init_state axiom forall bytes32 marketId. ghostMidnightNetCredit[marketId] == 0;
}

// Model of Midnight's take, for the two ways in which the adapter calls it: from take, as the taker, and from forceDeallocate, as the maker.
// The amounts and the data that Midnight gives to the callbacks are arbitrary. The loan token, which Midnight moves between the two callbacks, must not reenter the adapter.
function cvlTake(MidnightAdapter.Offer offer, uint256 units, address taker, address takerCallback) returns (uint256, uint256) {
    env e;
    bytes32 id;
    uint256 buyerAssets;
    uint256 sellerAssets;
    uint256 fee;
    address receiver;
    bytes data;

    require offer.maker != taker, "Midnight reverts with SelfTake";
    assert takerCallback == currentContract, "the adapter is always its own taker callback";

    if (taker != currentContract) {
        // forceDeallocate: the taker buys the sell offer of the adapter. Midnight calls onBuy on the taker callback.
        assert offer.maker == currentContract && !offer.buy && offer.callback == 0, "the adapter only makes its forced sell offer, without callback";
        onBuy(e, id, offer.market, buyerAssets, units, fee, taker, data);
    } else if (offer.buy) {
        // take: the adapter sells to the maker. Midnight calls the callback of the maker, then onSell.
        if (offer.callback != 0) havocCallback.callHavoc(e, offer.callback);
        onSell(e, id, offer.market, sellerAssets, units, fee, taker, receiver, data);
    } else {
        // take: the adapter buys from the maker. Midnight gives the credit to the adapter, calls onBuy, then calls the callback of the maker.
        require !currentContract.inForceDeallocate, "inForceDeallocate is only set during forceDeallocate";
        increaseMidnightNetCredit(id);
        onBuy(e, id, offer.market, buyerAssets, units, fee, taker, data);
        if (offer.callback != 0) havocCallback.callHavoc(e, offer.callback);
    }

    return (buyerAssets, sellerAssets);
}

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
