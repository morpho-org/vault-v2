// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function maxRate() external returns uint64 envfree;

    function _.realAssets() external => PER_CALLEE_CONSTANT;

    function _.canReceiveShares(address) external => PER_CALLEE_CONSTANT;
}

definition mulDivUp(uint256 x, uint256 y, uint256 z) returns mathint = (x * y + (z-1)) / z;

// Check how total assets change without interest accrual.
rule totalAssetsChange(method f) filtered {
    f -> !f.isView
} {
    env e1;
    env e2;
    env e3;
    require(e1.block.timestamp <= e2.block.timestamp, "setup timeline");
    require(e2.block.timestamp <= e3.block.timestamp, "setup timeline");

    require(e1.msg.sender != currentContract, "contracts cannot send transactions directly.");
    require(e2.msg.sender != currentContract, "contracts cannot send transactions directly.");
    require(e3.msg.sender != currentContract, "contracts cannot send transactions directly.");

    require(maxRate() == 0, "assume no interest accrual to count assets.");

    mathint totalAssetsPre = totalAssets(e1);

    uint256 addedAssets;
    uint256 removedAssets;

    if (f.selector == sig:deposit(uint,address).selector) {
        require(removedAssets == 0, "this operation only adds assets");
        deposit(e2, addedAssets, e2.msg.sender);
    } else if (f.selector == sig:mint(uint,address).selector) {
        require(removedAssets == 0, "this operation only adds assets");
        uint256 shares;
        require(addedAssets == previewMint(e1, shares), "Added assets should be the result of previewMint before the donation.");
        mint(e2, shares, e2.msg.sender);
    } else if (f.selector == sig:withdraw(uint,address,address).selector) {
        require(addedAssets == 0, "this operation only removes assets");
        withdraw(e2, removedAssets, e2.msg.sender, e2.msg.sender);
    } else if (f.selector == sig:redeem(uint,address,address).selector) {
        require(addedAssets == 0, "this operation only removes assets");
        uint256 shares;
        require(removedAssets == previewRedeem(e1, shares), "redeemed assets should be the result of previewRedeem before the donation");
        redeem(e2, shares, e2.msg.sender, e2.msg.sender);
    } else if (f.selector == sig:forceDeallocate(address,bytes,uint,address).selector) {
        require(addedAssets == 0, "this operation only removes assets");
        address adapter;
        bytes data;
        uint256 deallocationAmount;
        require(removedAssets == mulDivUp(deallocationAmount, currentContract.forceDeallocatePenalty[adapter], 10^18), "compute the penalty quoted in assets");
        forceDeallocate(e2, adapter, data, deallocationAmount, e2.msg.sender);
    } else {
        require(addedAssets == 0, "other operations don't add assets");
        require(removedAssets == 0, "other operations don't remove assets");
        calldataarg args;
        f(e2, args);
    }

    mathint totalAssetsPost = totalAssets(e3);

    assert totalAssetsPre + addedAssets - removedAssets == totalAssetsPost;
}
