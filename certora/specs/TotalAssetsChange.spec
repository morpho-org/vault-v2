// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function accrueInterestView() internal returns (uint256, uint256, uint256) => summaryAccrueInterestView();
}

// Assume that accrueInterest does nothing.
function summaryAccrueInterestView() returns (uint256, uint256, uint256) {
    return (currentContract._totalAssets, 0, 0);
}

definition mulDivUp(uint256 x, uint256 y, uint256 z) returns mathint = (x * y + (z - 1)) / z;

// Note that the case where the receiver is the vault itself goes through for withdraw and redeem, since it's _totalAssets that is checked and not actual balance which might not decrease for such cases.

// Calling deposit only adds assets equal to the amount deposited, assuming no interest accrual.
rule totalAssetsChangeDeposit(env e, uint256 assets, address receiver) {
    mathint totalAssetsPre = currentContract._totalAssets;

    deposit(e, assets, receiver);

    assert currentContract._totalAssets == totalAssetsPre + assets;
}

// Calling mint only adds assets equal to previewMint result, assuming no interest accrual.
rule totalAssetsChangeMint(env e, uint256 shares, address receiver) {
    mathint totalAssetsPre = currentContract._totalAssets;

    uint256 previewedAssets = previewMint(e, shares);

    mint(e, shares, receiver);

    assert currentContract._totalAssets == totalAssetsPre + previewedAssets;
}

// Calling withdraw only removes the withdrawn assets, assuming no interest accrual.
rule totalAssetsChangeWithdraw(env e, uint256 assets, address receiver, address owner) {
    mathint totalAssetsPre = currentContract._totalAssets;

    withdraw(e, assets, receiver, owner);

    assert currentContract._totalAssets == totalAssetsPre - assets;
}

// Calling redeem removes assets equal to previewRedeem result, assuming no interest accrual.
rule totalAssetsChangeRedeem(env e, uint256 shares, address receiver, address owner) {
    mathint totalAssetsPre = currentContract._totalAssets;

    uint256 previewedAssets = previewRedeem(e, shares);

    redeem(e, shares, receiver, owner);

    assert currentContract._totalAssets == totalAssetsPre - previewedAssets;
}

// Calling forceDeallocate removes assets based on penalty, assuming no interest accrual.
rule totalAssetsForceDeallocate(env e, address adapter, bytes data, uint256 deallocationAmount, address recipient) {
    mathint totalAssetsPre = currentContract._totalAssets;

    mathint penalty = mulDivUp(deallocationAmount, currentContract.forceDeallocatePenalty[adapter], 10 ^ 18);

    forceDeallocate(e, adapter, data, deallocationAmount, recipient);

    assert currentContract._totalAssets == totalAssetsPre - penalty;
}

// Other non-view functions don't change totalAssets, assuming no interest accrual.
rule totalAssetsUnchangedByOthers(env e, method f, calldataarg args)
filtered {
    f -> !f.isView &&
    f.selector != sig:deposit(uint256,address).selector &&
    f.selector != sig:mint(uint256,address).selector &&
    f.selector != sig:withdraw(uint256,address,address).selector &&
    f.selector != sig:redeem(uint256,address,address).selector &&
    f.selector != sig:forceDeallocate(address,bytes,uint256,address).selector
}
{
    mathint totalAssetsPre = currentContract._totalAssets;

    f(e, args);

    assert currentContract._totalAssets == totalAssetsPre;
}
