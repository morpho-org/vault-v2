// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// The adapter's net credit (credit minus pending fee) in each Midnight market.
persistent ghost mapping(bytes32 => uint128) ghostMidnightNetCredit {
    init_state axiom forall bytes32 marketId. ghostMidnightNetCredit[marketId] == 0;
}

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function MAX_MARKETS() external returns (uint256) envfree;

    // Same summaries as in MarketIdsMidnightAdapter.spec, where they are explained. The vault's accrueInterest and the token transfers are not summarized, so the strong invariants are checked at these calls.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    function _.updatePositionView(MidnightAdapter.Market, bytes32 id, address user) external => cvlUpdatePositionView(id, user) expect(uint128, uint128, uint128);
    function _.take(MidnightAdapter.Offer, bytes, uint256, address, address, address, bytes) external => HAVOC_ALL;
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

// Prove that the stored net credit is an upper bound of the adapter's net credit in Midnight.
strong invariant midnightNetCreditBelowStoredNetCredit()
    forall bytes32 marketId. ghostMidnightNetCredit[marketId] <= currentContract.marketData[marketId].netCredit
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
