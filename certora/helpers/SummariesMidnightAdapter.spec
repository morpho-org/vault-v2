// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// Model of the adapter's environment: Midnight, the parent vault and the asset are not in the scene.
// Assumes that external calls do not reenter the adapter.

methods {
    // The adapter's net credit in each market is tracked by ghostMidnightNetCredit.
    function currentNetCredit(bytes32 marketId) internal returns (uint128) => ghostMidnightNetCredit[marketId];

    // Summarized so that loops bounded by the number of markets or collateral params don't prune long lists or markets with many collaterals.
    // Remaining loops are bounded by the number of durations, which is at most MAX_DURATIONS = loop_iter.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // Non-view external calls can only decrease the adapter's Midnight net credits, through losses, withdrawals or sales.
    // Increases only happen in buys, which call onBuy (see increaseMidnightNetCredit).
    function _.take(MidnightAdapter.Offer, bytes, uint256, address, address, address, bytes) external => decreaseMidnightNetCreditsTake() expect(uint256, uint256);
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => decreaseMidnightNetCredits() expect void;
    function _.setConsumed(bytes32, uint128, address) external => decreaseMidnightNetCredits() expect void;
    function _.setIsAuthorized(address, bool, address) external => decreaseMidnightNetCredits() expect void;
    function _.accrueInterest() external => decreaseMidnightNetCredits() expect void;
    function _.allocate(address, bytes, uint256) external => decreaseMidnightNetCredits() expect void;
    function _.deallocate(address, bytes, uint256) external => decreaseMidnightNetCredits() expect void;

    // The asset is assumed to be a standard ERC20 token.
    function SafeERC20Lib.safeTransfer(address, address, uint256) internal => decreaseMidnightNetCredits();
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => decreaseMidnightNetCredits();
    function SafeERC20Lib.forceApproveMax(address, address) internal => decreaseMidnightNetCredits();
}

// The adapter's net credit (credit minus pending fee) in each Midnight market.
persistent ghost mapping(bytes32 => uint128) ghostMidnightNetCredit {
    init_state axiom forall bytes32 marketId. ghostMidnightNetCredit[marketId] == 0;
}

function decreaseMidnightNetCredits() {
    havoc ghostMidnightNetCredit assuming forall bytes32 marketId. ghostMidnightNetCredit@new[marketId] <= ghostMidnightNetCredit@old[marketId];
}

function decreaseMidnightNetCreditsTake() returns (uint256, uint256) {
    decreaseMidnightNetCredits();
    uint256 buyerAssets;
    uint256 sellerAssets;
    return (buyerAssets, sellerAssets);
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
