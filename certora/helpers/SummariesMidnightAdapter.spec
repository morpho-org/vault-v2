// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Model of the adapter's environment: the parent vault is linked, Midnight, the asset and the vault's other adapters and gates are not in the scene.
// Assumes that external calls do not reenter the adapter.

methods {
    // The adapter's net credit in each market is tracked by ghostMidnightNetCredit.
    function currentNetCredit(bytes32 marketId) internal returns (uint128) => ghostMidnightNetCredit[marketId];

    // Summarized because, with optimistic_loop, loops longer than loop_iter are pruned: durationAllocations loops over marketIds, so it would only allow short market lists, and ids returns at least 4 ids that the vault's allocate and deallocate loop over, so every path calling the vault would be pruned.
    // Remaining loops are over durations and over the summarized ids in the vault. They don't write the adapter's state, so paths with more iterations than loop_iter have counterparts with fewer iterations and the same market list.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // Views, resolved so that strong invariants are not checked at these calls (lossFactor is called in the middle of market list updates).
    function _.lossFactor(bytes32) external => NONDET;
    function _.liquidationLocked(bytes32, address) external => NONDET;

    // The id is a nested hash of the ABI-encoded market, which the prover handles poorly; any id is allowed.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // Midnight's take, called as taker by the adapter, either buys or sells the adapter's credit and calls back onBuy or onSell if the adapter is the taker callback.
    function _.take(MidnightAdapter.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) external => takeSummary(calledContract, offer, takerCallback, takerCallbackData) expect(uint256, uint256);

    // Withdrawals can only decrease the adapter's Midnight net credits.
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => decreaseMidnightNetCredits() expect void;

    // Calls that don't change the adapter's Midnight net credits, resolved so that they don't havoc the adapter's state.
    function _.setConsumed(bytes32, uint128, address) external => NONDET;

    // The vault's calls back into its adapters: the adapter's own allocate and deallocate, and views.
    // Other adapters are assumed to not reenter this adapter, so dispatching to this adapter is the only case that can change its state.
    // Statically, the dispatched deallocate can recurse into take and onSell, but the vault passes its own deallocate selector, so the dispatched deallocate returns before take: optimistic_summary_recursion prunes only these infeasible paths.
    function _.allocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);
    function _.deallocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);

    // The asset is assumed to be a standard ERC20 token.
    function SafeERC20Lib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeERC20Lib.forceApproveMax(address, address) internal => NONDET;
}

// The adapter's net credit (credit minus pending fee) in each Midnight market.
persistent ghost mapping(bytes32 => uint128) ghostMidnightNetCredit {
    init_state axiom forall bytes32 marketId. ghostMidnightNetCredit[marketId] == 0;
}

function decreaseMidnightNetCredits() {
    havoc ghostMidnightNetCredit assuming forall bytes32 marketId. ghostMidnightNetCredit@new[marketId] <= ghostMidnightNetCredit@old[marketId];
}

function takeSummary(address midnight, MidnightAdapter.Offer offer, address takerCallback, bytes takerCallbackData) returns (uint256, uint256) {
    bytes32 marketId;
    env e;
    require e.msg.sender == midnight, "Midnight calls back the taker";
    if (offer.buy) {
        // The adapter sells: its net credit in the market decreases, then Midnight calls onSell if the adapter is the taker callback (deallocate passes no callback).
        uint256 sellerAssets;
        uint256 soldCredit;
        uint256 sellPendingFeeDecrease;
        address receiver;
        decreaseMidnightNetCredits();
        if (takerCallback == currentContract) onSell(e, marketId, offer.market, sellerAssets, soldCredit, sellPendingFeeDecrease, currentContract, receiver, takerCallbackData);
    } else {
        // The adapter buys: its net credit in the market increases, then Midnight calls onBuy if the adapter is the taker callback.
        uint256 paidAssets;
        uint256 boughtCredit;
        uint256 buyPendingFeeIncrease;
        increaseMidnightNetCredit(marketId);
        if (takerCallback == currentContract) onBuy(e, marketId, offer.market, paidAssets, boughtCredit, buyPendingFeeIncrease, currentContract, takerCallbackData);
    }
    uint256 buyerAssets;
    uint256 sellerAssetsReturned;
    return (buyerAssets, sellerAssetsReturned);
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

// Midnight credits the bought units to the adapter before calling onBuy.
function increaseMidnightNetCredit(bytes32 marketId) {
    uint128 newNetCredit;
    ghostMidnightNetCredit[marketId] = newNetCredit;
}
