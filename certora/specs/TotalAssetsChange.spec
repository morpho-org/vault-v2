// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function accrueInterestView() internal returns(uint256, uint256, uint256) => summaryAccrueInterestView();
}

// Assume that accrueInterest does nothing.
function summaryAccrueInterestView() returns (uint256, uint256, uint256) {
    return (currentContract._totalAssets, 0, 0);
}

definition mulDivUp(uint256 x, uint256 y, uint256 z) returns mathint = (x * y + (z-1)) / z;

// Check how total assets change without interest accrual.
rule totalAssetsChange(env e, method f) filtered {
    f -> !f.isView
} {
    mathint totalAssetsPre = currentContract._totalAssets;

    uint256 addedAssets;
    uint256 removedAssets;

    if (f.selector == sig:deposit(uint,address).selector) {
        require(removedAssets == 0, "this operation only adds assets");
        deposit(e, addedAssets, e.msg.sender);
    } else if (f.selector == sig:mint(uint,address).selector) {
        uint256 shares;
        require(removedAssets == 0, "this operation only adds assets");
        require(addedAssets == previewMint(e, shares), "added assets should be the result of previewMint before the donation");
        mint(e, shares, e.msg.sender);
    } else if (f.selector == sig:withdraw(uint,address,address).selector) {
        require(addedAssets == 0, "this operation only removes assets");
        withdraw(e, removedAssets, e.msg.sender, e.msg.sender);
    } else if (f.selector == sig:redeem(uint,address,address).selector) {
        uint256 shares;
        require(addedAssets == 0, "this operation only removes assets");
        require(removedAssets == previewRedeem(e, shares), "redeemed assets should be the result of previewRedeem before the donation");
        redeem(e, shares, e.msg.sender, e.msg.sender);
    } else if (f.selector == sig:forceDeallocate(address,bytes,uint,address).selector) {
        address adapter;
        bytes data;
        uint256 deallocationAmount;
        require(addedAssets == 0, "this operation only removes assets");
        require(removedAssets == mulDivUp(deallocationAmount, currentContract.forceDeallocatePenalty[adapter], 10^18), "compute the penalty quoted in assets");
        forceDeallocate(e, adapter, data, deallocationAmount, e.msg.sender);
    } else {
        calldataarg args;
        require(addedAssets == 0, "other operations don't add assets");
        require(removedAssets == 0, "other operations don't remove assets");
        f(e, args);
    }

    mathint totalAssetsPost = currentContract._totalAssets;

    assert totalAssetsPre + addedAssets - removedAssets == totalAssetsPost;
}
