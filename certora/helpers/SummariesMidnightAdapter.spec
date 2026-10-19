// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Model of the adapter's environment: Midnight, the parent vault and the asset are not in the scene.
// Assumes that external calls do not reenter the adapter.

methods {
    // The adapter's net credit in each market is tracked by ghostMidnightNetCredit.
    function currentNetCredit(bytes32 marketId) internal returns (uint128) => ghostMidnightNetCredit[marketId];

    // Summarized so that loops bounded by the number of markets or collateral params don't prune long lists or markets with many collaterals.
    // Remaining loops are over durations and don't write the market list, so with optimistic_loop, paths with more durations than loop_iter have counterparts with fewer durations and the same market list.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // Views, resolved so that strong invariants are not checked at these calls (lossFactor is called in the middle of market list updates).
    function _.lossFactor(bytes32) external => NONDET;
    function _.liquidationLocked(bytes32, address) external => NONDET;
    function _.firstTotalAssets() external => NONDET;
    function _.absoluteCap(bytes32) external => NONDET;
    function _.relativeCap(bytes32) external => NONDET;

    // Arbitrary results, as the market list doesn't depend on rates and caps, to keep the solver away from nonlinear arithmetic.
    function MathLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function MathLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;

    // The id is a nested hash of the ABI-encoded market, which the prover handles poorly; any id is allowed.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // Midnight's take, called as taker by the adapter, either buys or sells the adapter's credit and calls back onBuy or onSell if the adapter is the taker callback.
    function _.take(MidnightAdapter.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) external => takeSummary(calledContract, offer, takerCallback, takerCallbackData) expect(uint256, uint256);

    // Withdrawals can only decrease the adapter's Midnight net credits.
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => decreaseMidnightNetCredits() expect void;

    // Calls that don't change the adapter's Midnight net credits, resolved so that they don't havoc the adapter's state.
    function _.setConsumed(bytes32, uint128, address) external => NONDET;
    function _.setIsAuthorized(address, bool, address) external => NONDET;
    function _.accrueInterest() external => NONDET;
    function _.allocate(address, bytes, uint256) external => NONDET;
    function _.deallocate(address, bytes, uint256) external => NONDET;

    // The asset is assumed to be a standard ERC20 token.
    function _.balanceOf(address) external => NONDET;
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
