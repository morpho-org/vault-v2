// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    // Assume that those calls produce deterministic results.
    function _.canSendShares(address) external => CONSTANT;
    function _.canSendAssets(address) external => CONSTANT;
    function _.canReceiveShares(address) external => CONSTANT;
    function _.canReceiveAssets(address) external => CONSTANT;

    function enter(uint256 assets, uint256 shares, address onBehalf) internal => summaryEnter(assets, shares, onBehalf);
    function exit(uint256 assets, uint256 shares, address receiver, address onBehalf) internal => summaryExit(assets, shares, receiver, onBehalf);
}

persistent ghost bool entered;

persistent ghost uint256 assetsEnter;

persistent ghost uint256 sharesEnter;

persistent ghost address onBehalfEnter;

function summaryEnter(uint256 assets, uint256 shares, address onBehalf) {
    if (entered) {
        assert assets == assetsEnter && shares == sharesEnter && onBehalf == onBehalfEnter;
    } else {
        entered = true;
        assetsEnter = assets;
        sharesEnter = shares;
        onBehalfEnter = onBehalf;
    }
}

persistent ghost bool exited;

persistent ghost uint256 assetsExit;

persistent ghost uint256 sharesExit;

persistent ghost address receiverExit;

persistent ghost address onBehalfExit;

function summaryExit(uint256 assets, uint256 shares, address receiver, address onBehalf) {
    if (exited) {
        assert assets == assetsExit && shares == sharesExit && receiver == receiverExit && onBehalf == onBehalfExit;
    } else {
        exited = true;
        assetsExit = assets;
        sharesExit = shares;
        receiverExit = receiver;
        onBehalfExit = onBehalf;
    }
}

rule depositMintEquivalence(env e, address onBehalf) {
    uint256 assetsInput;
    uint256 sharesInput;

    storage init = lastStorage;

    uint256 sharesOutput = deposit(e, assetsInput, onBehalf);
    storage afterDeposit = lastStorage;

    uint256 assetsOutput = mint(e, sharesInput, onBehalf) at init;
    storage afterMint = lastStorage;

    assert sharesOutput == sharesInput && assetsOutput == assetsInput => afterDeposit == afterMint;
}

rule withdrawRedeemEquivalence(env e, uint256 assets, address receiver, address onBehalf) {
    uint256 assetsInput;
    uint256 sharesInput;

    storage init = lastStorage;

    uint256 sharesOutput = withdraw(e, assetsInput, receiver, onBehalf);
    storage afterWithdraw = lastStorage;

    uint256 assetsOutput = redeem(e, sharesInput, receiver, onBehalf) at init;
    storage afterRedeem = lastStorage;

    assert sharesOutput == sharesInput && assetsOutput == assetsInput => afterWithdraw == afterRedeem;
}
