// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "MarketIdsMidnightAdapter.spec";

// The adapter's net credit (credit minus pending fee) in each Midnight market.
persistent ghost mapping(bytes32 => uint128) ghostMidnightNetCredit {
    init_state axiom forall bytes32 marketId. ghostMidnightNetCredit[marketId] == 0;
}

methods {
    function currentNetCredit(bytes32 marketId) internal returns (uint128) => readMidnightNetCredit(marketId);
}

// The adapter's net credit in Midnight can decrease at any time (sales, withdrawals, losses), so each read can return a lower value. It increases only when the adapter buys, which Midnight does before calling onBuy, checked as an entry point.
function readMidnightNetCredit(bytes32 marketId) returns uint128 {
    uint128 netCredit;
    require netCredit <= ghostMidnightNetCredit[marketId], "Midnight net credit only increases in buys";
    ghostMidnightNetCredit[marketId] = netCredit;
    return netCredit;
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
            requireInvariant midnightNetCreditBelowStoredNetCredit();
        }
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            requireInvariant midnightNetCreditBelowStoredNetCredit();
            increaseMidnightNetCredit(marketId);
        }
    }
