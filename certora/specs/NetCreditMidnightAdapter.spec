// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "MarketIdsMidnightAdapter.spec";

// The adapter's net credit (credit minus pending fee) in each Midnight market.
persistent ghost mapping(bytes32 => uint128) ghostMidnightNetCredit {
    init_state axiom forall bytes32 marketId. ghostMidnightNetCredit[marketId] == 0;
}

methods {
    function _.updatePositionView(MidnightAdapter.Market, bytes32 id, address user) external => cvlUpdatePositionView(id, user) expect(uint128, uint128, uint128);
    function _.take(MidnightAdapter.Offer, bytes, uint256, address, address, address, bytes) external => HAVOC_ALL;
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
            increaseMidnightNetCredit(marketId);
        }
    }

// Prove that a market with a non-zero stored net credit is in the list.
// This relies on midnightNetCreditBelowStoredNetCredit: withdrawToVault, onSell and deallocate store the adapter's net credit in Midnight without listing the market.
strong invariant nonZeroNetCreditIsListed()
    forall bytes32 marketId. currentContract.marketData[marketId].netCredit != 0 => currentContract.marketData[marketId].index < currentContract.marketIds.length && currentContract.marketIds[currentContract.marketData[marketId].index] == marketId
    {
        preserved {
            requireInvariant marketIdsLengthBounded();
            requireInvariant marketIdsIndex();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
        }
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            requireInvariant marketIdsLengthBounded();
            requireInvariant marketIdsIndex();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
            increaseMidnightNetCredit(marketId);
        }
    }
