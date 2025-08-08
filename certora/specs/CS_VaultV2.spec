// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

using VaultV2 as vaultv2;
using ERC20Mock as underlying;
using CSMockAdapter as simpleAdapter;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function allocation(bytes32) external returns uint256 envfree;

    function CSMockAdapter.adapterId() external returns (bytes32) envfree;
    function CSMockAdapter.allocation() external returns (uint256) envfree;
    function CSMockAdapter.deallocate(bytes, uint256, bytes4, address) external returns (bytes32[], int256) envfree;

    function ERC20Mock.balanceOf(address) external returns (uint256) envfree;
    function ERC20Mock.allowance(address, address) external returns (uint256) envfree;

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
rule giftingUnderlyingToVaultHasNoEffect(method f) filtered {
    // View functions are not interesting
    f -> !f.isView
} {
    env e1;
    env e2;
    env e3;
    require(e1.block.timestamp <= e2.block.timestamp, "e2 must happen after e1");
    require(e2.block.timestamp <= e3.block.timestamp, "e3 must happen after e2");

    require(vaultv2.asset == underlying, "Make sure we gift the vault's underlying.");

    require(e1.msg.sender != currentContract, "Cannot happen.");
    require(e2.msg.sender != currentContract, "Cannot happen.");
    require(e3.msg.sender != currentContract, "Cannot happen.");
    require(vaultv2.sharesGate == 0, "No need to make call resolution.");
    require(vaultv2.receiveAssetsGate == 0, "No need to make call resolution.");
    require(vaultv2.sendAssetsGate == 0, "No need to make call resolution.");

    // Todo: assume no interest.
    // No fees for simplicity
    require(vaultv2.performanceFee == 0);
    require(vaultv2.managementFee == 0);

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

// Check that given there is only one ID with a non-zero allocation, deallocation calls succeed only for that particular ID when one deallocates at most the allocated amount and reverts in all the other cases.
rule onlyAllocatedCanBeDeallocated() {
    env e;

    // Because we care about reverting executions, we need to be sure it can only revert where we want it to, aka when decreasing the allowance in deallocateInternal
    // that's why we need more requirements here

    // Disable fees for simplicity, having the fees is a mess here if we care about reverts
    require(vaultv2.performanceFee == 0, "For simplicity.");
    require(vaultv2.managementFee == 0, "For simplicity.");

    require(vaultv2.totalSupply + vaultv2.virtualShares < 2^256, "Needed otherwise minting the fees calculation might revert, even though it should be 0.");
    require(e.msg.sender != currentContract, "Cannot happen.");
    require(e.block.timestamp < 2^64, "Nothing too crazy so interest accrual doesn't die.");
    require(vaultv2.lastUpdate <= e.block.timestamp, "Make sure last update is in the past.");
    require(e.msg.value == 0, "Make sure we don't send ETH along, this would make the call revert.");
    require(vaultv2.isAllocator[e.msg.sender], "We need the caller to be whitelisted (allcator or sentinel).");

    bytes32 targetId = simpleAdapter.adapterId;
    uint256 targetAllocation = vaultv2.allocation(targetId);
    assert(simpleAdapter.allocation() == targetAllocation);

    uint256 amount;
    require(amount > 0, "We want to force deallocate to revert with underflow on allocation that are zero.");
    require(forall bytes32 id . vaultv2.caps[id].allocation == (id == targetId ? amount : 0), "Only the targetId has some allocation");

    mathint maxAmountSimpleAdapter = simpleAdapter.realAssets + simpleAdapter.realAssets/100;
    require(underlying.balanceOf(simpleAdapter) >= maxAmountSimpleAdapter, "We need the adapter to have enough funds, otherwise deallocate might revert because of lack of balance.");
    require(underlying.allowance(simpleAdapter, vaultv2) >= maxAmountSimpleAdapter, "Enforce the allowance is enough, for some reason the allowance given in the constructor doesn't seem to work.");

    require(simpleAdapter.realAssets + simpleAdapter.realAssets/100 < 2^256, "Needed otherwise interest might overflow in the adapter.");
    require(simpleAdapter.realAssets == targetAllocation, "This is an assumption we will need to prove. It is in the wishlist at the end of the file");

    bytes data;
    address adapter;
    require(vaultv2.isAdapter[adapter], "Make sure adapter is whitelisted.");

    vaultv2.deallocate@withrevert(e, adapter, data, amount);

    // If it did not revert it is because we touched the targetId, and only the targetId
    // If it did revert it is because we tried to touch an ID that did not have an allocation
    //  or we tried to deallocate too much from the correct ID
    assert !lastReverted => idTracker == targetId && adapter == simpleAdapter && amount <= maxAmountSimpleAdapter;
    assert lastReverted => idTracker != targetId || adapter != simpleAdapter
                            || (idTracker == targetId && adapter == simpleAdapter && amount > maxAmountSimpleAdapter);
}

// Check that accruing interest has no effect on the allocation.
// This allows us to assume no interest in allocationMovements rule because we showed that having an interest does not impact allocations.
rule accrueInterestDoesNotImpactAllocation() {
    env e;
    bytes32 id;
    uint256 allocationPre = vaultv2.allocation(id);
    vaultv2.accrueInterest(e);
    uint256 allocationPost = vaultv2.allocation(id);
    assert allocationPre == allocationPost;
}

// Summarize of the direction of the allocation mapping per function.
// Assumption: adapter are assumed/trusted to return the correct interest

/*
    Allocation can go up:
        * allocate
        * mint/deposit
        * deallocate/forceDeallocate (if interest > assets to deallocate)
        * redeem/withdraw (if interest > assets to deallocate)

    Allocation can go down:
        * deallocate/forceDeallocate
        * redeem/withdraw

    Allocation must not move:
        * all the other functions

    NOTE: there is a tautology for deallocate()/forceDeallocate()/redeem()/withdraw()
*/
rule allocationMovements(method f) filtered {
    f -> !f.isView
} {
    env e;
    require(e.msg.sender != currentContract, "Cannot happen.");
    // Todo: assume no interest.

    bytes32 id;
    uint256 allocationPre = vaultv2.allocation(id);

    calldataarg args;
    vaultv2.f(e, args);

    uint256 allocationPost = vaultv2.allocation(id);

    if (f.selector == sig:vaultv2.allocate(address,bytes,uint).selector) {
        // Allocation go up
        assert allocationPre <= allocationPost;
    } else if (vaultv2.liquidityAdapter != 0 && (f.selector == sig:vaultv2.deposit(uint,address).selector || f.selector == sig:vaultv2.mint(uint,address).selector)) {
        // Allocation go up
        assert allocationPre <= allocationPost;
    } else if (f.selector == sig:vaultv2.deallocate(address,bytes,uint).selector || f.selector == sig:vaultv2.forceDeallocate(address,bytes,uint,address).selector) {
        // Hard to test as it depends on the interest
        // Allocation can go up or down. This is a tautology and another rule should check the actual direction of allocation based on the deallocated assets and interest returned by the adapter
        assert (allocationPre <= allocationPost) || (allocationPre >= allocationPost);
    } else if (vaultv2.liquidityAdapter != 0 && (f.selector == sig:vaultv2.withdraw(uint,address,address).selector || f.selector == sig:vaultv2.redeem(uint,address,address).selector)) {
        // Hard to test as it call deallocate and thus depends on the interest
        // Allocation can go up or down. This is a tautology and another rule should check the actual direction of allocation based on the deallocated assets and interest returned by the adapter
        assert (allocationPre <= allocationPost) || (allocationPre >= allocationPost);
    } else {
        // Allocation does not move
        assert allocationPre == allocationPost;
    }
}

// Check that mint/deposit allow the allocation to go from zero to non-zero only if there is a liquidity adapter set.
// This allows allocationCanOnlyBecomeNonZeroThroughAllocateWithoutLiquidityAdapter to not set a liquidity adapter for simplicity.
rule depositAllocation(method f) filtered {
    f -> f.selector == sig:vaultv2.deposit(uint,address).selector ||
         f.selector == sig:vaultv2.mint(uint,address).selector
} {
    env e;
    require(e.msg.sender != currentContract, "Cannot happen.");
    require(e.msg.value == 0, "No function is payable.");
    require(vaultv2.sharesGate == 0, "No need to make call resolution.");
    require(vaultv2.receiveAssetsGate == 0, "No need to make call resolution.");
    require(vaultv2.sendAssetsGate == 0, "No need to make call resolution.");
    // Todo: assume no interest.

    require(forall bytes32 id . vaultv2.caps[id].allocation == 0, "Start with all allocations to 0.");

    bytes32 id;
    uint256 allocationPre = vaultv2.allocation(id);

    calldataarg args;
    vaultv2.f(e, args);

    uint256 allocationPost = vaultv2.allocation(id);

    bool allocationWentUp = (allocationPre < allocationPost);
    bool allocationStayedZero = (allocationPre == allocationPost) && (allocationPre == 0);

    assert allocationWentUp => vaultv2.liquidityAdapter != 0;
    assert (allocationWentUp && !allocationStayedZero) || (!allocationWentUp && allocationStayedZero); // Only one can be true at a time (xor keyword seems to be only for int/uint/bytesK...)
}

/*
    - when no liquidity adapter is set, allocation can only go from zero to non-zero via an allocate() call

    NOTE: this rule is vacuous for deallocate() and forceDeallocate() as the prover cannot find a non-reverting scenario
            when all the allocations are 0. But this is fine as it is what we want (impossibility to deallocate()/forceDeallocate() if allocation == 0).
*/
rule allocationCanOnlyBecomeNonZeroThroughAllocateWithoutLiquidityAdapter(env e, method f, calldataarg args) filtered {
     // View functions are not interesting
    f -> !f.isView
      && f.selector != sig:forceDeallocate(address,bytes,uint,address).selector // We can do this thanks to rule onlyDeallocationIfNoAllocation
      && f.selector != sig:deallocate(address,bytes,uint).selector // We can do this thanks to rule onlyDeallocationIfNoAllocation

} {
    require(e.msg.sender != currentContract, "Cannot happen.");
    require(vaultv2.sharesGate == 0, "No need to make call resolution.");
    require(vaultv2.receiveAssetsGate == 0, "No need to make call resolution.");
    require(vaultv2.sendAssetsGate == 0, "No need to make call resolution.");
    require(vaultv2.liquidityAdapter == 0, "We can do this thanks to rule allocationCanOnlyIncreaseOnMintDepositWithLiquidityAdapter.");
    // Todo: assume no interest.

    require(forall bytes32 id . vaultv2.caps[id].allocation == 0, "Start with all allocations to 0.");

    bytes32 id;
    uint256 allocationPre = vaultv2.allocation(id);

    vaultv2.f(e, args);

    uint256 allocationPost = vaultv2.allocation(id);

    // Non reverting calls must come from allocate, deposit or mint (last two only if there is a liquidity adapter which is not the case here)
    bool allocationWentUp = allocationPre < allocationPost;
    bool allocationStayedZero = (allocationPre == allocationPost) && (allocationPre == 0);

    assert allocationWentUp => f.selector == sig:vaultv2.allocate(address,bytes,uint).selector;
    assert !allocationWentUp => allocationStayedZero;
}

rule noDeallocationIfNoAllocation(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:forceDeallocate(address,bytes,uint,address).selector
      || f.selector == sig:deallocate(address,bytes,uint).selector
}
{
    require(forall bytes32 id . vaultv2.caps[id].allocation == 0, "Start with all allocations to 0.");

    vaultv2.f@withrevert(e, args);

    assert lastReverted;
}
