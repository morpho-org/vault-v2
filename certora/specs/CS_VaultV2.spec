// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

using VaultV2 as vaultv2;
using ERC20Mock as underlying;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function allocation(bytes32) external returns uint256 envfree;
    function maxRate() external returns uint64 envfree;
}

definition mulDivUp(uint256 x, uint256 y, uint256 z) returns mathint = (x * y + (z-1)) / z;

// Check how total assets change without interest accrual.
rule totalAssetsChanges(method f) filtered {
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

    require(vaultv2.maxRate() == 0, "assume no interest accrual to count assets.");

    mathint totalAssetsPre = vaultv2.totalAssets(e1);

    uint256 addedAssets;
    uint256 removedAssets;

    if (f.selector == sig:deposit(uint,address).selector) {
        require(removedAssets == 0, "this operation only adds assets");
        vaultv2.deposit(e2, addedAssets, e2.msg.sender);
    } else if (f.selector == sig:mint(uint,address).selector) {
        require(removedAssets == 0, "this operation only adds assets");
        uint256 shares;
        require(addedAssets == vaultv2.previewMint(e1, shares), "Added assets should be the result of previewMint before the donation.");
        vaultv2.mint(e2, shares, e2.msg.sender);
    } else if (f.selector == sig:withdraw(uint,address,address).selector) {
        require(addedAssets == 0, "this operation only removes assets");
        vaultv2.withdraw(e2, removedAssets, e2.msg.sender, e2.msg.sender);
    } else if (f.selector == sig:redeem(uint,address,address).selector) {
        require(addedAssets == 0, "this operation only removes assets");
        uint256 shares;
        require(removedAssets == vaultv2.previewRedeem(e1, shares), "redeemed assets should be the result of previewRedeem before the donation");
        vaultv2.redeem(e2, shares, e2.msg.sender, e2.msg.sender);
    } else if (f.selector == sig:forceDeallocate(address,bytes,uint,address).selector) {
        require(addedAssets == 0, "this operation only removes assets");
        address adapter;
        bytes data;
        uint256 deallocationAmount;
        require(removedAssets == mulDivUp(deallocationAmount, vaultv2.forceDeallocatePenalty[adapter], 10^18), "compute the penalty quoted in assets");
        vaultv2.forceDeallocate(e2, adapter, data, deallocationAmount, e2.msg.sender);
    } else {
        require(addedAssets == 0);
        require(removedAssets == 0);
        calldataarg args;
        vaultv2.f(e2, args);
    }

    mathint totalAssetsPost = vaultv2.totalAssets(e3);

    assert totalAssetsPre + addedAssets - removedAssets == totalAssetsPost;
}

// Check that accruing interest has no effect on the allocation.
rule accrueInterestDoesNotImpactAllocation() {
    env e;
    bytes32 id;
    uint256 allocationPre = vaultv2.allocation(id);
    vaultv2.accrueInterest(e);
    uint256 allocationPost = vaultv2.allocation(id);
    assert allocationPre == allocationPost;
}

// Check that only function able to change allocation are deposit, mint, withdraw, redeem, allocation, deallocate, forceDeallocate.
rule functionsChangingAllocation(env e, method f, calldataarg args) filtered {
    f -> !f.isView &&
         f.selector != sig:vaultv2.deposit(uint,address).selector &&
         f.selector != sig:vaultv2.mint(uint,address).selector &&
         f.selector != sig:vaultv2.withdraw(uint,address,address).selector &&
         f.selector != sig:vaultv2.redeem(uint,address,address).selector &&
         f.selector != sig:vaultv2.allocate(address,bytes,uint).selector &&
         f.selector != sig:vaultv2.deallocate(address,bytes,uint).selector &&
         f.selector != sig:vaultv2.forceDeallocate(address,bytes,uint,address).selector
} {
    bytes32 id;
    uint256 allocationPre = vaultv2.allocation(id);

    vaultv2.f(e, args);

    uint256 allocationPost = vaultv2.allocation(id);

    assert allocationPost == allocationPre;
}

// Check that mint/deposit/withdraw/redeem can make an allocation non-zero only if there is a liquidity adapter set.
rule depositWithdrawChangeAllocationThroughLiquidityAdapter(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:vaultv2.deposit(uint,address).selector ||
         f.selector == sig:vaultv2.mint(uint,address).selector ||
         f.selector != sig:vaultv2.withdraw(uint,address,address).selector ||
         f.selector != sig:vaultv2.redeem(uint,address,address).selector
} {
    require(e.msg.sender != currentContract, "contracts cannot send transactions directly");
    require(e.msg.value == 0, "speed up the prover, functions are non-payable");

    require(forall bytes32 id . vaultv2.caps[id].allocation == 0, "assume no allocation");

    bytes32 id;
    uint256 allocationPre = vaultv2.allocation(id);

    vaultv2.f(e, args);

    uint256 allocationPost = vaultv2.allocation(id);

    assert allocationPost != allocationPre => vaultv2.liquidityAdapter != 0;
}

// Check that when no liquidity adapter is set, allocation can only go from zero to non-zero via an allocate() call.
rule allocationCanOnlyBecomeNonZeroThroughAllocateWithoutLiquidityAdapter(env e, method f, calldataarg args) filtered {
    f -> !f.isView &&
         // Checked in noDeallocationIfNoAllocation.
         f.selector != sig:forceDeallocate(address,bytes,uint,address).selector &&
         f.selector != sig:deallocate(address,bytes,uint).selector

} {
    require(e.msg.sender != currentContract, "contracts cannot send transactions directly");

    require(vaultv2.liquidityAdapter == 0, "assume no liquidity adapter");
    require(forall bytes32 id . vaultv2.caps[id].allocation == 0, "assume no allocation");

    bytes32 id;
    uint256 allocationPre = vaultv2.allocation(id);

    vaultv2.f(e, args);

    uint256 allocationPost = vaultv2.allocation(id);

    bool allocationWentUp = allocationPre < allocationPost;
    bool allocationStayedZero = (allocationPre == allocationPost) && (allocationPre == 0);

    assert allocationWentUp => f.selector == sig:vaultv2.allocate(address,bytes,uint).selector;
    assert !allocationWentUp => allocationStayedZero;
}

rule noDeallocationIfNoAllocation(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:forceDeallocate(address,bytes,uint,address).selector ||
         f.selector == sig:deallocate(address,bytes,uint).selector
}
{
    require(forall bytes32 id . vaultv2.caps[id].allocation == 0, "assume no allocation");

    vaultv2.f@withrevert(e, args);

    assert lastReverted;
}
