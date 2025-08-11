// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

using VaultV2 as vaultv2;
using ERC20Mock as underlying;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function allocation(bytes32) external returns uint256 envfree;
    function maxRate() external returns uint64 envfree;

    function ERC20Mock.balanceOf(address) external returns uint256 envfree;
    function ERC20Mock.allowance(address, address) external returns uint256 envfree;

    function _.canReceiveShares(address) external => NONDET;
    function _.canSendShares(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
}

persistent ghost bytes32 idTracker;

hook Sstore VaultV2.caps[KEY bytes32 id].allocation uint256 a {
    idTracker = id;
}

definition YEAR() returns uint256 = 365 * 24 * 60 * 60;
definition WAD() returns uint256 = 10^18;
definition mulDivUp(uint256 x, uint256 y, uint256 z) returns mathint = (x * y + (z-1)) / z;

// Check how total assets change without interest accrual.
rule totalAssetsChanges(method f) filtered {
    f -> !f.isView
} {
    env e1;
    env e2;
    env e3;
    require(e1.block.timestamp <= e2.block.timestamp, "e2 must happen after e1");
    require(e2.block.timestamp <= e3.block.timestamp, "e3 must happen after e2");

    require(e1.msg.sender != currentContract, "Cannot happen.");
    require(e2.msg.sender != currentContract, "Cannot happen.");
    require(e3.msg.sender != currentContract, "Cannot happen.");

    require(vaultv2.maxRate() == 0, "Assume no interest accrual to count assets.");

    mathint totalAssetsPre = vaultv2.totalAssets(e1);

    uint256 addedAssets;
    uint256 removedAssets;

    if (f.selector == sig:deposit(uint,address).selector) {
        require(removedAssets == 0,  "We only add assets.");
        vaultv2.deposit(e2, addedAssets, e2.msg.sender);
    } else if (f.selector == sig:mint(uint,address).selector) {
        require(removedAssets == 0, "We only add assets.");
        uint256 shares;
        require(addedAssets == vaultv2.previewMint(e1, shares), "Added assets should be the result of previewMint before the donation.");
        vaultv2.mint(e2, shares, e2.msg.sender);
    } else if (f.selector == sig:withdraw(uint,address,address).selector) {
        require(addedAssets == 0, "We only remove assets.");
        vaultv2.withdraw(e2, removedAssets, e2.msg.sender, e2.msg.sender);
    } else if (f.selector == sig:redeem(uint,address,address).selector) {
        require(addedAssets == 0, "We only remove assets.");
        uint256 shares;
        require(removedAssets == vaultv2.previewRedeem(e1, shares), "Redeemed assets should be the result of previewRedeem before the donation.");
        vaultv2.redeem(e2, shares, e2.msg.sender, e2.msg.sender);
    } else if (f.selector == sig:forceDeallocate(address,bytes,uint,address).selector) {
        require(addedAssets == 0, "We only remove assets.");
        address adapter;
        bytes data;
        uint256 deallocationAmount;
        require(removedAssets == mulDivUp(deallocationAmount, vaultv2.forceDeallocatePenalty[adapter], WAD()), "This replicates what should happen on the contract level.");
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

// Check that mint/deposit/withdraw/redeem change the allocation only if there is a liquidity adapter set.
rule depositWithdrawChangeAllocationThroughLiquidityAdapter(method f) filtered {
    f -> f.selector == sig:vaultv2.deposit(uint,address).selector ||
         f.selector == sig:vaultv2.mint(uint,address).selector ||
         f.selector != sig:vaultv2.withdraw(uint,address,address).selector ||
         f.selector != sig:vaultv2.redeem(uint,address,address).selector
} {
    env e;
    require(e.msg.sender != currentContract, "Cannot happen.");
    require(e.msg.value == 0, "No function is payable.");
    require(vaultv2.sharesGate == 0, "No need to make call resolution.");
    require(vaultv2.receiveAssetsGate == 0, "No need to make call resolution.");
    require(vaultv2.sendAssetsGate == 0, "No need to make call resolution.");

    require(forall bytes32 id . vaultv2.caps[id].allocation == 0, "Start with all allocations to 0.");

    bytes32 id;
    uint256 allocationPre = vaultv2.allocation(id);

    calldataarg args;
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
    require(e.msg.sender != currentContract, "Cannot happen.");
    require(vaultv2.sharesGate == 0, "No need to make call resolution.");
    require(vaultv2.receiveAssetsGate == 0, "No need to make call resolution.");
    require(vaultv2.sendAssetsGate == 0, "No need to make call resolution.");
    require(vaultv2.liquidityAdapter == 0, "We can do this thanks to rule allocationCanOnlyIncreaseOnMintDepositWithLiquidityAdapter.");

    require(forall bytes32 id . vaultv2.caps[id].allocation == 0, "Start with all allocations to 0.");

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
    require(forall bytes32 id . vaultv2.caps[id].allocation == 0, "Start with all allocations to 0.");

    vaultv2.f@withrevert(e, args);

    assert lastReverted;
}
