// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// ERC4626 round-trip properties (a16z erc4626-tests/ERC4626.prop.sol L244-318):
// no round trip lets a user extract more value than they put in, e.g.
// previewRedeem(previewDeposit(a)) <= a and previewWithdraw(previewMint(s)) >= s.
// Interest and fee accrual are summarized to arbitrary but fixed totals via
// accrueInterestView (a sound over-approximation that removes the adapter loop
// and external reads), and virtualShares is assumed positive so the mulDiv
// denominators are nonzero.

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
    require to_mathint(currentContract.virtualShares) > 0;
    assert convertToAssets(convertToShares(assets)) <= assets;
}

rule convertRoundTripShares(uint256 shares) {
    require to_mathint(currentContract.virtualShares) > 0;
    assert convertToShares(convertToAssets(shares)) <= shares;
}

rule roundTripDepositRedeem(uint256 assets) {
    require to_mathint(currentContract.virtualShares) > 0;
    assert previewRedeem(previewDeposit(assets)) <= assets;
}

rule roundTripDepositWithdraw(uint256 assets) {
    require to_mathint(currentContract.virtualShares) > 0;
    assert previewWithdraw(assets) >= previewDeposit(assets);
}

rule roundTripRedeemDeposit(uint256 shares) {
    require to_mathint(currentContract.virtualShares) > 0;
    assert previewDeposit(previewRedeem(shares)) <= shares;
}

rule roundTripRedeemMint(uint256 shares) {
    require to_mathint(currentContract.virtualShares) > 0;
    assert previewMint(shares) >= previewRedeem(shares);
}

rule roundTripMintWithdraw(uint256 shares) {
    require to_mathint(currentContract.virtualShares) > 0;
    assert previewWithdraw(previewMint(shares)) >= shares;
}

rule roundTripMintRedeem(uint256 shares) {
    require to_mathint(currentContract.virtualShares) > 0;
    assert previewRedeem(shares) <= previewMint(shares);
}

rule roundTripWithdrawMint(uint256 assets) {
    require to_mathint(currentContract.virtualShares) > 0;
    assert previewMint(previewWithdraw(assets)) >= assets;
}

rule roundTripWithdrawDeposit(uint256 assets) {
    require to_mathint(currentContract.virtualShares) > 0;
    assert previewDeposit(assets) <= previewWithdraw(assets);
}
