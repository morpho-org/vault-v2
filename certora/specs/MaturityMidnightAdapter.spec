// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "NetCreditMidnightAdapter.spec";

function requireMarketListInvariants() {
    requireInvariant marketIdsLengthBounded();
    requireInvariant marketIdsIndex();
    requireInvariant listedHasNonZeroNetCredit();
    requireInvariant midnightNetCreditBelowStoredNetCredit();
    requireInvariant nonZeroNetCreditIsListed();
}

// Prove that the stored maturity of a market doesn't change while the adapter holds net credit in it.
rule maturityImmutable(env e, method f, calldataarg args, bytes32 marketId) filtered { f -> f.selector != sig:onBuy(bytes32, MidnightAdapter.Market, uint256, uint256, uint256, address, bytes).selector } {
    requireMarketListInvariants();
    uint48 maturityBefore = currentContract.marketData[marketId].maturity;
    uint128 netCreditBefore = currentContract.marketData[marketId].netCredit;

    f(e, args);

    assert netCreditBefore != 0 && currentContract.marketData[marketId].netCredit != 0 => currentContract.marketData[marketId].maturity == maturityBefore;
}

// Same as maturityImmutable for onBuy, which Midnight calls after crediting the adapter.
rule maturityImmutableOnBuy(env e, bytes32 marketId, bytes32 boughtMarketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) {
    requireMarketListInvariants();
    uint48 maturityBefore = currentContract.marketData[marketId].maturity;
    uint128 netCreditBefore = currentContract.marketData[marketId].netCredit;

    increaseMidnightNetCredit(boughtMarketId);
    onBuy(e, boughtMarketId, market, paidAssets, boughtCredit, buyPendingFeeIncrease, buyer, callbackData);

    assert netCreditBefore != 0 && currentContract.marketData[marketId].netCredit != 0 => currentContract.marketData[marketId].maturity == maturityBefore;
}
