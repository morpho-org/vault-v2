// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/SummariesMidnightAdapter.spec";

methods {
    function MAX_MARKETS() external returns (uint256) envfree;
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
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
        }
    }
