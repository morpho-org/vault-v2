// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

methods {
    function asset() external returns (address) envfree;
    function midnight() external returns (address) envfree;
    function inForceDeallocate() external returns (bool) envfree;

    // Every call of the adapter to a Midnight function that changes a market position.
    function _.take(MidnightAdapter.Offer offer, bytes, uint256, address, address, address, bytes) external => recordTake(offer) expect(uint256, uint256);
    function _.withdraw(MidnightAdapter.Market market, uint256, address, address) external => recordWithdraw(market) expect void;

    // Midnight authorizations decide which takes the adapter can be part of without calling Midnight itself.
    function _.setIsAuthorized(address, bool, address) external => recordSetIsAuthorized() expect void;

    // The id is a nested hash of the ABI-encoded market, which the prover handles poorly; any id is allowed.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;
}

// Loan tokens of the markets touched through take or withdraw. Persistent so that unresolved calls don't reset it; reentrant calls are checked by the parametric rule on their own entry point.
persistent ghost mapping(address => bool) touchedLoanToken;

persistent ghost bool setIsAuthorizedCalled;

function recordTake(MidnightAdapter.Offer offer) returns (uint256, uint256) {
    touchedLoanToken[offer.market.loanToken] = true;
    uint256 buyerAssets;
    uint256 sellerAssets;
    return (buyerAssets, sellerAssets);
}

function recordWithdraw(MidnightAdapter.Market market) {
    touchedLoanToken[market.loanToken] = true;
}

function recordSetIsAuthorized() {
    setIsAuthorizedCalled = true;
}

// Check that no entry point takes or withdraws on a market whose loan token is not the vault's asset.
rule noTouchWrongLoanToken(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address token;
    require token != asset(), "token is any loan token other than the asset";
    require !touchedLoanToken[token], "not touched before the call";

    f(e, args);

    assert !touchedLoanToken[token];
}

// Check that the adapter never changes its Midnight authorizations after construction, where it only authorizes itself.
rule noSetIsAuthorized(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    require !setIsAuthorizedCalled, "not called before the call";

    f(e, args);

    assert !setIsAuthorizedCalled;
}

// Check that the adapter only ratifies offers on markets with the asset as loan token, except during forceDeallocate's take.
rule isRatifiedChecksLoanToken(env e, MidnightAdapter.Offer offer, bytes ratifierData, address taker) {
    isRatified(e, offer, ratifierData, taker);

    assert inForceDeallocate() || offer.market.loanToken == asset();
}

// Check that onBuy reverts unless the adapter is the buyer, except during forceDeallocate's take.
rule onBuyOnlyAsBuyer(env e, bytes32 id, MidnightAdapter.Market market, uint256 buyerAssets, uint256 units, uint256 pendingFeeIncrease, address buyer, bytes data) {
    bool wasInForceDeallocate = inForceDeallocate();

    onBuy(e, id, market, buyerAssets, units, pendingFeeIncrease, buyer, data);

    assert e.msg.sender == midnight();
    assert wasInForceDeallocate || buyer == currentContract;
}

// Check that onSell reverts unless the adapter is the seller.
rule onSellOnlyAsSeller(env e, bytes32 id, MidnightAdapter.Market market, uint256 sellerAssets, uint256 units, uint256 pendingFeeDecrease, address seller, address receiver, bytes data) {
    onSell(e, id, market, sellerAssets, units, pendingFeeDecrease, seller, receiver, data);

    assert e.msg.sender == midnight();
    assert seller == currentContract;
}

// Set when the entry point itself writes true to inForceDeallocate. Writes by reentrant calls are checked by the parametric rule on their own entry point.
persistent ghost bool inForceDeallocateSet;

hook Tstore inForceDeallocate bool newValue {
    if (newValue) inForceDeallocateSet = true;
}

// Check that only forceDeallocate sets inForceDeallocate, which it does after checking the market's loan token.
rule inForceDeallocateOnlyInForceDeallocate(env e, method f, calldataarg args) filtered { f -> !f.isView && f.selector != sig:deallocate(bytes, uint256, bytes4, address).selector } {
    require !inForceDeallocateSet, "not set before the call";

    f(e, args);

    assert !inForceDeallocateSet;
}

rule deallocateSetsFlagOnlyForForceDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
    require !inForceDeallocateSet, "not set before the call";

    deallocate(e, data, assets, selector, sender);

    // IVaultV2.forceDeallocate(address,bytes,uint256,address).selector
    assert inForceDeallocateSet => selector == to_bytes4(0xe4d38cd8);
}
