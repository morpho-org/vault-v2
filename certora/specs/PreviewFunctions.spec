// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function _.realAssets() external => PER_CALLEE_CONSTANT;
    function _.canReceiveShares(address) external => PER_CALLEE_CONSTANT;
}

rule previewDepositValue(env e, uint256 assets, address onBehalf) {
    require e.block.timestamp < 2^64;
    uint256 previewDepositValue = previewDeposit(e, assets);
    uint256 depositValue = deposit(e, assets, onBehalf);
    assert previewDepositValue == depositValue;
}

rule previewDepositRevert(env e, uint256 assets, address onBehalf) {
    require e.block.timestamp < 2^64;
    previewDeposit@withrevert(e, assets);
    bool previewDepositWentThrough = !lastReverted;
    deposit@withrevert(e, assets, onBehalf);
    bool depositWentThrough = !lastReverted;
    assert depositWentThrough => previewDepositWentThrough;
}

rule previewMintValue(env e, uint256 shares, address onBehalf) {
    require e.block.timestamp < 2^64;
    uint256 previewMintValue = previewMint(e, shares);
    uint256 mintValue = mint(e, shares, onBehalf);
    assert previewMintValue == mintValue;
}


rule previewMintRevert(env e, uint256 shares, address onBehalf) {
    require e.block.timestamp < 2^64;
    previewMint@withrevert(e, shares);
    bool previewMintWentThrough = !lastReverted;
    mint@withrevert(e, shares, onBehalf);
    bool mintWentThrough = !lastReverted;
    assert mintWentThrough => previewMintWentThrough;
}

rule previewWithdrawValue(env e, uint256 assets, address receiver, address onBehalf) {
    require e.block.timestamp < 2^64;
    uint256 previewWithdrawValue = previewWithdraw(e, assets);
    uint256 withdrawValue = withdraw(e, assets, receiver, onBehalf);
    assert previewWithdrawValue == withdrawValue;
}

rule previewWithdrawRevert(env e, uint256 assets, address receiver, address onBehalf) {
    require e.block.timestamp < 2^64;
    previewWithdraw@withrevert(e, assets);
    bool previewWithdrawWentThrough = !lastReverted;
    withdraw@withrevert(e, assets, receiver, onBehalf);
    bool withdrawWentThrough = !lastReverted;
    assert withdrawWentThrough => previewWithdrawWentThrough;
}

rule previewRedeemValue(env e, uint256 shares, address receiver, address onBehalf) {
    require e.block.timestamp < 2^64;
    uint256 previewRedeemValue = previewRedeem(e, shares);
    uint256 redeemValue = redeem(e, shares, receiver, onBehalf);
    assert previewRedeemValue == redeemValue;
}

rule previewRedeemRevert(env e, uint256 shares, address receiver, address onBehalf) {
    require e.block.timestamp < 2^64;
    previewRedeem@withrevert(e, shares);
    bool previewRedeemWentThrough = !lastReverted;
    redeem@withrevert(e, shares, receiver, onBehalf);
    bool redeemWentThrough = !lastReverted;
    assert redeemWentThrough => previewRedeemWentThrough;
}
