// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Model of the adapter's environment: the parent vault is linked, Midnight, the asset and the vault's other adapters and gates are not in the scene.
// Assumes that external calls do not reenter the adapter: properties are checked on the body of each function, and Midnight's callbacks (onBuy, onSell) and the vault's calls into the adapter are checked as entry points of their own.
methods {
    // A multicall is a sequence of the other calls, which are each checked.
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

// Prove that a market with a non-zero stored maturity has a non-zero stored net credit.
strong invariant nonZeroMaturityHasNonZeroNetCredit()
    forall bytes32 marketId. currentContract.marketData[marketId].maturity != 0 => currentContract.marketData[marketId].netCredit != 0;

// Whether a zero net credit has been stored for the market, as the adapter does before removing a market.
persistent ghost mapping(bytes32 => bool) ghostZeroNetCreditStored;

hook Sstore currentContract.marketData[KEY bytes32 marketId].netCredit uint128 netCredit {
    if (netCredit == 0) ghostZeroNetCreditStored[marketId] = true;
}

// Prove that a call changes a non-zero stored maturity only by resetting it to zero, and only if it also stores a zero net credit for the market, as when the market is removed.
// The net credit can be non-zero again at the end of the call: in this model, Midnight's net credit can be any value, so withdrawToVault can store a non-zero net credit after onBuy removed the market.
// This is a property of each call: across calls, a market can be removed and bought again, and in the adapter it then gets the same maturity because the market id commits to the maturity, which this model abstracts.
rule maturityImmutable(env e, method f, calldataarg args, bytes32 marketId) {
    requireInvariant nonZeroMaturityHasNonZeroNetCredit();
    require !ghostZeroNetCreditStored[marketId], "no zero net credit stored yet in this call";
    uint48 maturityBefore = currentContract.marketData[marketId].maturity;

    f(e, args);

    uint48 maturityAfter = currentContract.marketData[marketId].maturity;
    assert maturityBefore != 0 && maturityAfter != maturityBefore => maturityAfter == 0 && ghostZeroNetCreditStored[marketId];
}
