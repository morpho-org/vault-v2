// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Mock as asset;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function accrueInterestView() internal returns(uint256, uint256, uint256) => summaryAccrueInterestView();

}

// Assume that accrueInterest does nothing.
function summaryAccrueInterestView() returns (uint256, uint256, uint256) {
    return (currentContract._totalAssets, 0, 0);
}

definition mulDivUp(uint256 x, uint256 y, uint256 z) returns mathint = (x * y + (z-1)) / z;

// NOTE : receiver == currentContract case is okay since it's _totalAssets that is checked and not actual balance which might not increase/decrease for such cases

// Calling deposit only adds assets equal to the amount deposited, assuming no interest accrual.
rule totalAssetsChangeDeposit(env e, uint256 assets, address receiver) {
    mathint totalAssetsPre = currentContract._totalAssets;
    
    deposit(e, assets, receiver);
    
    assert currentContract._totalAssets == totalAssetsPre + assets;
}

// mint only adds assets equal to previewMint result
rule totalAssetsChangeMint(env e, uint256 shares, address receiver) {
    mathint totalAssetsPre = currentContract._totalAssets;
    uint256 previewedAssets = previewMint(e, shares);
    
    mint(e, shares, receiver);
    
    assert currentContract._totalAssets == totalAssetsPre + previewedAssets;
}

// withdraw only removes the withdrawn assets
rule totalAssetsChangeWithdraw(env e, uint256 assets, address receiver, address owner) {
    mathint totalAssetsPre = currentContract._totalAssets;
    
    withdraw(e, assets, receiver, owner);
    
    assert currentContract._totalAssets == totalAssetsPre - assets;
}

// redeem removes assets equal to previewRedeem result
rule totalAssetsChangeRedeem(env e, uint256 shares, address receiver, address owner) {
    mathint totalAssetsPre = currentContract._totalAssets;
    uint256 previewedAssets = previewRedeem(e, shares);
    
    redeem(e, shares, receiver, owner);
    
    assert currentContract._totalAssets == totalAssetsPre - previewedAssets;
}

// forceDeallocate removes assets based on penalty
rule totalAssetsForceDeallocate(env e, address adapter, bytes data, uint256 deallocationAmount, address recipient) {
    mathint totalAssetsPre = currentContract._totalAssets;
    
    mathint penalty = mulDivUp(deallocationAmount, currentContract.forceDeallocatePenalty[adapter], 10^18);
    
    forceDeallocate(e, adapter, data, deallocationAmount, recipient);
    
    assert currentContract._totalAssets == totalAssetsPre - penalty;
}

// other non-view functions don't change totalAssets
rule totalAssetsUnchangedByOthers(env e, method f) 
    filtered {
        f -> !f.isView && 
        f.selector != sig:deposit(uint,address).selector &&
        f.selector != sig:mint(uint,address).selector &&
        f.selector != sig:withdraw(uint,address,address).selector &&
        f.selector != sig:redeem(uint,address,address).selector &&
        f.selector != sig:forceDeallocate(address,bytes,uint,address).selector
    } 
{
    mathint totalAssetsPre = currentContract._totalAssets;
    calldataarg args;
    
    f(e, args);
    
    assert currentContract._totalAssets == totalAssetsPre;
}

