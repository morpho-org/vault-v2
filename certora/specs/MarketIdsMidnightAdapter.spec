// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    function MAX_MARKETS() external returns (uint256) envfree;
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
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

// Prove that the market list has at most MAX_MARKETS entries.
strong invariant marketIdsLengthBounded()
    currentContract.marketIds.length <= MAX_MARKETS();

// Prove that the index stored for each listed market is its position in the list.
strong invariant marketIdsIndex()
    forall uint256 i. i < currentContract.marketIds.length => currentContract.marketData[currentContract.marketIds[i]].index == i
    {
        preserved {
            requireInvariant marketIdsLengthBounded();
            requireInvariant nonZeroNetCreditIsListed();
            requireInvariant listedHasNonZeroNetCredit();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
        }
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            requireInvariant marketIdsLengthBounded();
            requireInvariant nonZeroNetCreditIsListed();
            requireInvariant listedHasNonZeroNetCredit();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
            increaseMidnightNetCredit(marketId);
        }
    }

// Prove that a market with a non-zero stored net credit is in the list.
strong invariant nonZeroNetCreditIsListed()
    forall bytes32 marketId. currentContract.marketData[marketId].netCredit != 0 => currentContract.marketData[marketId].index < currentContract.marketIds.length && currentContract.marketIds[currentContract.marketData[marketId].index] == marketId
    {
        preserved {
            requireInvariant marketIdsLengthBounded();
            requireInvariant marketIdsIndex();
            requireInvariant listedHasNonZeroNetCredit();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
        }
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            requireInvariant marketIdsLengthBounded();
            requireInvariant marketIdsIndex();
            requireInvariant listedHasNonZeroNetCredit();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
            increaseMidnightNetCredit(marketId);
        }
    }

// Prove that a market in the list has a non-zero stored net credit.
strong invariant listedHasNonZeroNetCredit()
    forall uint256 i. i < currentContract.marketIds.length => currentContract.marketData[currentContract.marketIds[i]].netCredit != 0
    {
        preserved {
            requireInvariant marketIdsLengthBounded();
            requireInvariant marketIdsIndex();
            requireInvariant nonZeroNetCreditIsListed();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
        }
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            requireInvariant marketIdsLengthBounded();
            requireInvariant marketIdsIndex();
            requireInvariant nonZeroNetCreditIsListed();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
            increaseMidnightNetCredit(marketId);
        }
    }
