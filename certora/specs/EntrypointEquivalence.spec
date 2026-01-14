// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    // Assume that the ERC20 is ERC20Standard.
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

    // Assume that the only adapter is the market v1 adapter.
    function _.realAssets() external => DISPATCHER(true);

    // Assume that those calls produce deterministic results.
    function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => CONSTANT;
    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => CONSTANT;
    function _.canSendShares(address) external => CONSTANT;
    function _.canSendAssets(address) external => CONSTANT;
    function _.canReceiveShares(address) external => CONSTANT;
    function _.canReceiveAssets(address) external => CONSTANT;

    function _.accrueInterest(MorphoHarness.MarketParams) external => DISPATCHER;
    function _.allocation(bytes32) external => DISPATCHER;
    function _.supply(MorphoHarness.MarketParams, uint256, uint256, address, bytes) external => DISPATCHER;
    function _.withdraw(MorphoHarness.MarketParams, uint256, uint256, address, address) external => DISPATCHER;
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
