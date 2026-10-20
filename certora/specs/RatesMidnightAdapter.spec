// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Model of the adapter's environment: the parent vault is linked, Midnight, the asset and the vault's other adapters and gates are not in the scene.
// Assumes that external calls do not reenter the adapter: properties are checked on the body of each function, and Midnight's callbacks (onBuy, onSell) and the vault's calls into the adapter are checked as entry points of their own.
methods {
    function maxTtm() external returns (uint32) envfree;
    function minNetBuyRate() external returns (uint64) envfree;
    function maxNetSellRate() external returns (uint64) envfree;
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // The adapter's net credit in Midnight can be any value.
    function currentNetCredit(bytes32 marketId) internal returns (uint128) => NONDET;

    // Summarized because, with optimistic_loop, loops longer than loop_iter are pruned: durationAllocations loops over marketIds, so it would only allow short market lists, and ids returns at least 4 ids.
    // Remaining loops are over durations and over ids in the vault. They don't write the adapter's state, so paths with more iterations than loop_iter have counterparts with fewer iterations and the same market list.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // Views, resolved so that strong invariants are not checked at these calls (lossFactor is called in the middle of market list updates).
    function _.lossFactor(bytes32) external => NONDET;
    function _.liquidationLocked(bytes32, address) external => NONDET;

    // The id is a nested hash of the ABI-encoded market, which the prover handles poorly; any id is allowed.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // Calls into Midnight, resolved so that they don't havoc the adapter's state. Midnight's take doesn't call back the adapter.
    function _.take(MidnightAdapter.Offer, bytes, uint256, address, address, address, bytes) external => NONDET;
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => NONDET;
    function _.setConsumed(bytes32, uint128, address) external => NONDET;

    // The vault's calls into its adapters, which don't reenter this adapter.
    function _.allocate(bytes, uint256, bytes4, address) external => NONDET;
    function _.deallocate(bytes, uint256, bytes4, address) external => NONDET;

    // Views called by the vault's accrueInterest, resolved so that strong invariants are not checked at these calls (onBuy calls accrueInterest after Midnight credits the adapter, before the adapter records it).
    function _.realAssets() external => NONDET;
    function _.canReceiveShares(address) external => NONDET;
    function _.balanceOf(address) external => NONDET;

    // The asset is assumed to be a standard ERC20 token.
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

// Prove that a buy succeeds only if the market's time to maturity is at most maxTtm, and the net rate of the buy is at least minNetBuyRate.
rule buyRespectsGuardrails(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) {
    onBuy(e, marketId, market, paidAssets, boughtCredit, buyPendingFeeIncrease, buyer, callbackData);

    mathint ttm = market.maturity - e.block.timestamp;
    mathint boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
    assert ttm > 0 && ttm <= maxTtm();
    assert (boughtNetCredit - paidAssets) * WAD() >= minNetBuyRate() * ttm * paidAssets;
}

// Prove that a sale succeeds only if its price is at least minForceSellPrice in forceSellable markets, and its net rate is at most maxNetSellRate in other markets.
rule sellRespectsGuardrails(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 sellerAssets, uint256 soldCredit, uint256 sellPendingFeeDecrease, address seller, address receiver, bytes callbackData) {
    bool forceSellable = currentContract.marketData[marketId].forceSellable;
    mathint minForceSellPrice = currentContract.marketData[marketId].minForceSellPrice;

    onSell(e, marketId, market, sellerAssets, soldCredit, sellPendingFeeDecrease, seller, receiver, callbackData);

    mathint ttm = market.maturity > e.block.timestamp ? market.maturity - e.block.timestamp : 0;
    mathint soldNetCredit = soldCredit - sellPendingFeeDecrease;
    assert forceSellable => sellerAssets * WAD() >= soldNetCredit * minForceSellPrice;
    assert !forceSellable => sellerAssets * (WAD() + maxNetSellRate() * ttm) >= soldNetCredit * WAD();
}
