// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association

using Midnight as midnight;
using VaultV2 as vault;
using LoanToken as loanToken;
using CollateralToken as collateralToken;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // currentNetCredit reads block.timestamp through updatePositionView, so the CVL call takes env.
    function currentNetCredit(bytes32) internal returns (uint128);

    function midnight.updatePositionView(MidnightAdapter.Market, bytes32, address) external returns (uint128, uint128, uint128);
    function midnight.totalUnits(bytes32) external returns (uint128) envfree;
    function midnight.continuousFeeCredit(bytes32) external returns (uint128) envfree;

    // LoanToken and CollateralToken are ERC20Standard. The asset immutables are LoanToken.
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.approve(address, uint256) external => DISPATCHER(true);
    function _.allowance(address, address) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

    // offer.ratifier is an arbitrary address. The dispatcher sends isRatified to DummyRatifier or this adapter.
    // This adapter requires maker == address(this), and take passes itself as taker, which Midnight rejects.
    function _.isRatified(MidnightAdapter.Offer, bytes, address) external => DISPATCHER(true);

    // The low-level token.call in safeApprove does not resolve to approve. These tokens' approve only writes the allowance.
    function SafeERC20Lib.safeApprove(address token, address spender, uint256 value) internal => cvlSafeApprove(token, spender, value);

    // ids hashes ABI-encoded market fields. Without this summary the prover does not resolve Midnight calls in functions that call ids.
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // toId is a nested hash of the ABI-encoded market. The ghost is an arbitrary function of the market's scalar fields, so one such market has one id, and take and withdrawToVault are not forced through create2.
    function IdLib.toId(MidnightAdapter.Market memory market) internal returns (bytes32) => arbitraryToId(market);
}

// The adapter is not its own sub-ratifier, so the sub-ratifier call in isRatified does not dispatch back to it.
hook Sload bool value isSubRatifier[KEY address ratifier] {
    require ratifier != currentContract || !value, "the adapter is not its own sub-ratifier";
}

// Same scalar fields and collateral count, same id. A ghost cannot take Market, because of the collateral array. Any id is allowed.
ghost ghostToId(uint256, address, address, uint256, uint256, uint256, address, address) returns bytes32;

function arbitraryToId(MidnightAdapter.Market market) returns bytes32 {
    return ghostToId(market.chainId, market.midnight, market.loanToken, market.collateralParams.length, market.maturity, market.rcfThreshold, market.enterGate, market.liquidatorGate);
}

function arbitraryIds() returns bytes32[] {
    bytes32[] idsArray;
    return idsArray;
}

// Post-slash credit before the pending fee. Maturity 0 accrues no fee, as in currentNetCredit.
function currentCredit(env e, bytes32 marketId) returns uint128 {
    MidnightAdapter.Market dummyMarket;
    require dummyMarket.maturity == 0, "the dummy market accrues no fee";
    uint128 credit;
    uint128 pendingFee;
    uint128 accruedFee;
    credit, pendingFee, accruedFee = midnight.updatePositionView(e, dummyMarket, marketId, currentContract);
    return credit;
}

// Calls approve as the adapter. The library is inlined, so the token sees the adapter as msg.sender.
function cvlSafeApprove(address token, address spender, uint256 value) {
    env e;
    require e.msg.sender == currentContract, "the adapter is the caller of approve";
    require e.msg.value == 0, "approve is not paid";
    if (token == loanToken) {
        loanToken.approve(e, spender, value);
    } else if (token == collateralToken) {
        collateralToken.approve(e, spender, value);
    }
}

// c is this adapter's credit before the pending fee. n is that credit minus the pending fee. y is Midnight's totalUnits.
// totalUnits tracks gross credit, so a call preserves y >= c. y >= n follows because the pending fee is nonnegative.
rule adapterNetCreditBelowMarketTotal(method f, env e, calldataarg args, bytes32 marketId) {
    require currentContract.midnight == midnight, "read the Midnight instance the adapter calls";
    require currentContract.parentVault == vault, "read the vault the adapter calls";
    require vault.adapters.length == 1 && vault.adapters[0] == currentContract, "the vault lists only this adapter";
    require(forall address account. vault.isAdapter[account] == (account == currentContract)), "the vault recognizes only this adapter";

    uint128 c = currentCredit(e, marketId);
    uint128 y = midnight.totalUnits(marketId);
    require y >= c, "Midnight's totalUnits covers this adapter's credit";

    f(e, args);

    uint128 cPrime = currentCredit(e, marketId);
    uint128 nPrime = currentNetCredit(e, marketId);
    uint128 yPrime = midnight.totalUnits(marketId);
    assert yPrime >= cPrime, "the call keeps totalUnits above this adapter's credit";
    assert yPrime >= nPrime, "the call keeps totalUnits above this adapter's net credit";
}

// n is this adapter's net credit. m is totalUnits minus continuousFeeCredit, the lenders' credit after the accrued fee.
// Accrual moves a fee from credit into continuousFeeCredit and leaves net credit unchanged, so a call preserves m >= c.
// m >= n follows because the pending fee is nonnegative.
rule adapterNetCreditBelowMarketNetCredit(method f, env e, calldataarg args, bytes32 marketId) {
    require currentContract.midnight == midnight, "read the Midnight instance the adapter calls";
    require currentContract.parentVault == vault, "read the vault the adapter calls";
    require vault.adapters.length == 1 && vault.adapters[0] == currentContract, "the vault lists only this adapter";
    require(forall address account. vault.isAdapter[account] == (account == currentContract)), "the vault recognizes only this adapter";

    uint128 c = currentCredit(e, marketId);
    mathint m = midnight.totalUnits(marketId) - midnight.continuousFeeCredit(marketId);
    require m >= c, "the market's net credit covers this adapter's credit";

    f(e, args);

    uint128 cPrime = currentCredit(e, marketId);
    uint128 nPrime = currentNetCredit(e, marketId);
    mathint mPrime = midnight.totalUnits(marketId) - midnight.continuousFeeCredit(marketId);
    assert mPrime >= cPrime, "the call keeps the market's net credit above this adapter's credit";
    assert mPrime >= nPrime, "the call keeps the market's net credit above this adapter's net credit";
}
