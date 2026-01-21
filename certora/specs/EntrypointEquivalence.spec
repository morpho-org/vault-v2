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

persistent ghost uint256 assetsEnter;

persistent ghost uint256 sharesEnter;

persistent ghost address onBehalfEnter;

function summaryEnter(uint256 assets, uint256 shares, address onBehalf) {
    assetsEnter = assets;
    sharesEnter = shares;
    onBehalfEnter = onBehalf;
}

persistent ghost uint256 assetsExit;

persistent ghost uint256 sharesExit;

persistent ghost address receiverExit;

persistent ghost address onBehalfExit;

function summaryExit(uint256 assets, uint256 shares, address receiver, address onBehalf) {
    assetsExit = assets;
    sharesExit = shares;
    receiverExit = receiver;
    onBehalfExit = onBehalf;
}

rule depositMintEquivalenceForEnter(env e, address onBehalf) {
    uint256 assetsInput;
    uint256 sharesInput;

    uint256 sharesOutput = deposit(e, assetsInput, onBehalf);
    address onBehalfDeposit = onBehalfEnter;
    uint256 assetsDeposit = assetsEnter;
    uint256 sharesDeposit = sharesEnter;

    uint256 assetsOutput = mint(e, sharesInput, onBehalf);
    address onBehalfMint = onBehalfEnter;
    uint256 assetsMint = assetsEnter;
    uint256 sharesMint = sharesEnter;

    assert sharesOutput == sharesInput && assetsOutput == assetsInput => 
        onBehalfDeposit == onBehalfMint && 
        assetsDeposit == assetsMint && 
        sharesDeposit == sharesMint;
}

rule withdrawRedeemEquivalenceForExit(env e, uint256 assets, address receiver, address onBehalf) {
    uint256 assetsInput;
    uint256 sharesInput;

    uint256 sharesOutput = withdraw(e, assetsInput, receiver, onBehalf);
    address receiverWithdraw = receiverExit;
    address onBehalfWithdraw = onBehalfExit;
    uint256 assetsWithdraw = assetsExit;
    uint256 sharesWithdraw = sharesExit;

    uint256 assetsOutput = redeem(e, sharesInput, receiver, onBehalf);
    address receiverRedeem = receiverExit;
    address onBehalfRedeem = onBehalfExit;
    uint256 assetsRedeem = assetsExit;
    uint256 sharesRedeem = sharesExit;

    assert sharesOutput == sharesInput && assetsOutput == assetsInput => 
        receiverWithdraw == receiverRedeem && 
        onBehalfWithdraw == onBehalfRedeem && 
        assetsWithdraw == assetsRedeem && 
        sharesWithdraw == sharesRedeem;
}
