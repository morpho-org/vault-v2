// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    function MAX_MARKETS() external returns (uint256) envfree;
}

// Prove that the stored net credit is an upper bound of the adapter's net credit in Midnight.
strong invariant midnightNetCreditBelowStoredNetCredit()
    forall bytes32 marketId. ghostMidnightNetCredit[marketId] <= currentContract.marketData[marketId].netCredit
    filtered { f -> f.selector != sig:multicall(bytes[]).selector } {
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            increaseMidnightNetCredit(marketId);
        }
    }

// Prove that the market list has at most MAX_MARKETS entries.
strong invariant marketIdsLengthBounded()
    currentContract.marketIds.length <= MAX_MARKETS()
    filtered { f -> f.selector != sig:multicall(bytes[]).selector }

// Prove that the index stored for each listed market is its position in the list.
strong invariant marketIdsIndex()
    forall uint256 i. i < currentContract.marketIds.length => currentContract.marketData[currentContract.marketIds[i]].index == i
    filtered { f -> f.selector != sig:multicall(bytes[]).selector } {
        preserved {
            requireInvariant marketIdsLengthBounded();
            requireInvariant listedIffNonZeroNetCredit();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
        }
        preserved onBuy(bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) with (env e) {
            requireInvariant marketIdsLengthBounded();
            requireInvariant listedIffNonZeroNetCredit();
            requireInvariant midnightNetCreditBelowStoredNetCredit();
            increaseMidnightNetCredit(marketId);
        }
    }

// Prove that a market is in the list if and only if its stored net credit is non-zero.
strong invariant listedIffNonZeroNetCredit()
    forall bytes32 marketId. currentContract.marketData[marketId].netCredit != 0 <=> (currentContract.marketData[marketId].index < currentContract.marketIds.length && currentContract.marketIds[currentContract.marketData[marketId].index] == marketId)
    filtered { f -> f.selector != sig:multicall(bytes[]).selector } {
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
