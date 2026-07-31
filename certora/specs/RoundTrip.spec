// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// inspired by https://github.com/a16z/erc4626-tests/blob/ac485460e014f22807c1ff687e0b4dc3af96ee40/ERC4626.test.sol#L251-L317

methods {
    function convertToShares(uint256) external returns (uint256) envfree;
    function convertToAssets(uint256) external returns (uint256) envfree;
    function previewDeposit(uint256) external returns (uint256) envfree;
    function previewMint(uint256) external returns (uint256) envfree;
    function previewWithdraw(uint256) external returns (uint256) envfree;
    function previewRedeem(uint256) external returns (uint256) envfree;

    function VaultV2.accrueInterestView() internal returns (uint256, uint256, uint256) => summaryAccrueInterestView();
}

ghost uint256 gNewTotalAssets;

ghost uint256 gPerformanceFeeShares;

ghost uint256 gManagementFeeShares;

function summaryAccrueInterestView() returns (uint256, uint256, uint256) {
    return (gNewTotalAssets, gPerformanceFeeShares, gManagementFeeShares);
}

rule convertRoundTripAssets(uint256 assets) {
    assert convertToAssets(convertToShares(assets)) <= assets;
}

rule convertRoundTripShares(uint256 shares) {
    assert convertToShares(convertToAssets(shares)) <= shares;
}

rule roundTripDepositRedeem(uint256 assets) {
    assert previewRedeem(previewDeposit(assets)) <= assets;
}

rule roundTripDepositWithdraw(uint256 assets) {
    assert previewWithdraw(assets) >= previewDeposit(assets);
}

rule roundTripRedeemDeposit(uint256 shares) {
    assert previewDeposit(previewRedeem(shares)) <= shares;
}

rule roundTripRedeemMint(uint256 shares) {
    assert previewMint(shares) >= previewRedeem(shares);
}

rule roundTripMintWithdraw(uint256 shares) {
    assert previewWithdraw(previewMint(shares)) >= shares;
}

rule roundTripMintRedeem(uint256 shares) {
    assert previewRedeem(shares) <= previewMint(shares);
}

rule roundTripWithdrawMint(uint256 assets) {
    assert previewMint(previewWithdraw(assets)) >= assets;
}

rule roundTripWithdrawDeposit(uint256 assets) {
    assert previewDeposit(assets) <= previewWithdraw(assets);
}
