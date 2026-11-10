// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Same summaries as in MarketIdsMidnightAdapter.spec, where they are explained.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // The id is a nested hash of the ABI-encoded market, which the prover handles poorly; any id is allowed.
    // The id is a ghost so that deallocateRevertsInForceRemovedMarket can refer to it. No call computes the id of two different markets.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => globalMarketId;
}

// The id of the market given to the adapter, when the adapter computes it from the market.
persistent ghost bytes32 globalMarketId;

function arbitraryIds() returns bytes32[] {
    bytes32[] idsArray;
    return idsArray;
}

function arbitraryAllocations(uint256 length) returns uint256[] {
    uint256[] allocations;
    require allocations.length == length, "durationAllocations returns length allocations";
    return allocations;
}

// Prove that a force removed market has a zero stored net credit.
strong invariant forceRemovedHasZeroNetCredit()
    forall bytes32 marketId. currentContract.marketData[marketId].forceRemoved => currentContract.marketData[marketId].netCredit == 0;

// Check that a buy reverts in a force removed market.
rule buyRevertsInForceRemovedMarket(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 paidAssets, uint256 boughtCredit, uint256 buyPendingFeeIncrease, address buyer, bytes callbackData) {
    require !currentContract.inForceDeallocate, "assume the adapter is not in forceDeallocate";
    require currentContract.marketData[marketId].forceRemoved, "assume the market is force removed";

    onBuy@withrevert(e, marketId, market, paidAssets, boughtCredit, buyPendingFeeIncrease, buyer, callbackData);

    assert lastReverted;
}

// Check that a sale reverts in a force removed market.
rule saleRevertsInForceRemovedMarket(env e, bytes32 marketId, MidnightAdapter.Market market, uint256 sellerAssets, uint256 soldCredit, uint256 sellPendingFeeDecrease, address seller, address receiver, bytes callbackData) {
    require currentContract.marketData[marketId].forceRemoved, "assume the market is force removed";

    onSell@withrevert(e, marketId, market, sellerAssets, soldCredit, sellPendingFeeDecrease, seller, receiver, callbackData);

    assert lastReverted;
}

// Check that a withdrawal and a force deallocation revert in a force removed market.
rule deallocateRevertsInForceRemovedMarket(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
    require sender != currentContract, "assume the call is a withdrawal or a force deallocation, not a change that the adapter reports itself";
    require currentContract.marketData[globalMarketId].forceRemoved, "assume the market is force removed";

    deallocate@withrevert(e, data, assets, selector, sender);

    assert lastReverted;
}

// Check that a force removal cannot be deactivated.
rule forceRemovalCannotBeDeactivated(env e, method f, calldataarg args, bytes32 marketId) {
    require currentContract.marketData[marketId].forceRemoved, "assume the market is force removed";

    f@withrevert(e, args);

    assert currentContract.marketData[marketId].forceRemoved;
}
