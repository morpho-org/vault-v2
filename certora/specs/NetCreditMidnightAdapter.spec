// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "MarketIdsMidnightAdapter.spec";

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
