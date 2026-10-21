// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// The parent vault is linked. Midnight, the asset and the vault's other adapters and gates are not in the scene.
// The guardrails are checked before any call that can write the adapter's state, and the rules only use values read before the call, so most external calls are left unresolved.
methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function maxTtm() external returns (uint32) envfree;
    function minNetBuyRate() external returns (uint64) envfree;
    function maxNetSellRate() external returns (uint64) envfree;
    function noSalesWithShortfall() external returns (bool) envfree;

    // Over-approximation because we don't look at reverts in this file.
    function currentNetCredit(bytes32 marketId) internal returns (uint128) => NONDET;
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // Summarized because, with optimistic_loop, loops longer than loop_iter are pruned: durationAllocations loops over marketIds, so it would only allow short market lists, and ids returns at least 4 ids.
    // Remaining loops are over durations and over ids in the vault. They don't write the adapter's state, so paths with more iterations than loop_iter have counterparts with fewer iterations and the same market list.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // The asset is assumed to be a standard ERC20 token, that does not reenter VaultV2 nor the Midnight adapter.
    function SafeERC20Lib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeERC20Lib.forceApproveMax(address, address) internal => NONDET;
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

definition WAD() returns mathint = 10 ^ 18;

// Check that a buy succeeds only if the market is not forceSellable, its time to maturity is at most maxTtm, and the net rate of the buy is at least minNetBuyRate.
rule buyRespectsGuardrails(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) {
    mathint maxTtmSeconds = maxTtm();
    mathint minNetBuyRatePerSecond = minNetBuyRate();
    bool forceSellable = currentContract.marketData[marketId].forceSellable;

    onBuy(e, marketId, market, paidAssets, boughtCredit, buyPendingFeeIncrease, buyer, callbackData);

    mathint ttm = market.maturity - e.block.timestamp;
    mathint boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
    assert !forceSellable;
    assert ttm > 0 && ttm <= maxTtmSeconds;

    // In real numbers: (boughtNetCredit - paidAssets) / paidAssets >= minNetBuyRatePerSecond * ttm / WAD, written without division.
    assert (boughtNetCredit - paidAssets) * WAD() >= minNetBuyRatePerSecond * ttm * paidAssets;
}

// Check that a sale succeeds only if its price is at least minForceSellPrice in forceSellable markets, and, in other markets, its net rate is at most maxNetSellRate and it has no shortfall when noSalesWithShortfall is set.
rule sellRespectsGuardrails(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 sellerAssets, uint256 soldCredit, uint256 sellPendingFeeDecrease, address seller, address receiver, bytes callbackData) {
    bool forceSellable = currentContract.marketData[marketId].forceSellable;
    mathint minForceSellPrice = currentContract.marketData[marketId].minForceSellPrice;
    mathint maxNetSellRatePerSecond = maxNetSellRate();
    bool salesWithShortfallDisabled = noSalesWithShortfall();

    // onSell updates the market's net rate, so the guardrail uses the value before the sale.
    mathint netRatePerSecondBefore = currentContract.marketData[marketId].netRate;

    onSell(e, marketId, market, sellerAssets, soldCredit, sellPendingFeeDecrease, seller, receiver, callbackData);

    mathint ttm = market.maturity > e.block.timestamp ? market.maturity - e.block.timestamp : 0;
    mathint soldNetCredit = soldCredit - sellPendingFeeDecrease;
    assert forceSellable => sellerAssets * WAD() >= soldNetCredit * minForceSellPrice;
    assert !forceSellable => sellerAssets * (WAD() + maxNetSellRatePerSecond * ttm) >= soldNetCredit * WAD();
    assert !forceSellable && salesWithShortfallDisabled => sellerAssets * (WAD() + netRatePerSecondBefore * ttm) >= soldNetCredit * WAD();
}
