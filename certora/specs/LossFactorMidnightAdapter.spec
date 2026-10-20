// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Model of the adapter's environment: the parent vault is linked, Midnight, the asset and the vault's other adapters and gates are not in the scene.
// Assumes that external calls do not reenter the adapter: properties are checked on the body of each function, and Midnight's callbacks (onBuy, onSell) and the vault's calls into the adapter are checked as entry points of their own.
methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // The adapter's net credit in Midnight can be any value.
    function currentNetCredit(bytes32 marketId) internal returns (uint128) => NONDET;

    // Summarized because, with optimistic_loop, loops longer than loop_iter are pruned: durationAllocations loops over marketIds, so it would only allow short market lists, and ids returns at least 4 ids.
    // Remaining loops are over durations and over ids in the vault. They don't write the adapter's state, so paths with more iterations than loop_iter have counterparts with fewer iterations and the same market list.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // Views, resolved so that strong invariants are not checked at these calls (lossFactor is called in the middle of market list updates).
    // Midnight's loss factor can be any value; the values returned for each market are recorded.
    function _.lossFactor(bytes32 marketId) external => lossFactorSummary(marketId) expect(uint128);
    function _.liquidationLocked(bytes32, address) external => NONDET;

    // The id is a nested hash of the ABI-encoded market, which the prover handles poorly; any id is allowed.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // Calls into Midnight, resolved so that they don't havoc the adapter's state. Midnight's take doesn't call back the adapter.
    function _.take(MidnightAdapter.Offer, bytes, uint256, address, address, address, bytes) external => NONDET;
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => NONDET;
    function _.setConsumed(bytes32, uint128, address) external => NONDET;

    // The vault's calls into its adapters, which don't reenter this adapter.
    function _.allocate(bytes, uint256, bytes4, address) external => arbitraryAdapterResult() expect(bytes32[], int256);
    function _.deallocate(bytes, uint256, bytes4, address) external => arbitraryAdapterResult() expect(bytes32[], int256);

    // Views called by the vault's accrueInterest, resolved so that strong invariants are not checked at these calls (onBuy calls accrueInterest after Midnight credits the adapter, before the adapter records it).
    function _.realAssets() external => NONDET;
    function _.canReceiveShares(address) external => NONDET;
    function _.balanceOf(address) external => NONDET;

    // The asset is assumed to be a standard ERC20 token.
    function SafeERC20Lib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeERC20Lib.forceApproveMax(address, address) internal => NONDET;
}

function arbitraryAdapterResult() returns (bytes32[], int256) {
    bytes32[] idsArray;
    int256 change;
    return (idsArray, change);
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

// Whether Midnight returned a given loss factor for a market.
persistent ghost mapping(bytes32 => mapping(uint128 => bool)) ghostMidnightLossFactorReturned;

function lossFactorSummary(bytes32 marketId) returns uint128 {
    uint128 lossFactor;
    ghostMidnightLossFactorReturned[marketId][lossFactor] = true;
    return lossFactor;
}

// Prove that a call changes the stored loss factor of a market only to a loss factor that Midnight returned for that market during the call, or to zero together with the stored net credit, as when the market is removed.
// This does not prove that the stored loss factor is at most Midnight's current one, which also needs Midnight's loss factor to never decrease.
rule lossFactorIsMidnightLossFactor(env e, method f, calldataarg args, bytes32 marketId) {
    require forall uint128 lossFactor. !ghostMidnightLossFactorReturned[marketId][lossFactor];
    uint128 lossFactorBefore = currentContract.marketData[marketId].lossFactor;

    f(e, args);

    uint128 lossFactorAfter = currentContract.marketData[marketId].lossFactor;
    assert lossFactorAfter != lossFactorBefore => ghostMidnightLossFactorReturned[marketId][lossFactorAfter] || (lossFactorAfter == 0 && currentContract.marketData[marketId].netCredit == 0);
}
