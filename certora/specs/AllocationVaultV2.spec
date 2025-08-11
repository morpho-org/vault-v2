// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function allocation(bytes32) external returns uint256 envfree;
}

// Check that accruing interest has no effect on the allocation.
rule accrueInterestDoesNotImpactAllocation(env e) {
    bytes32 id;
    uint256 allocationPre = allocation(id);

    accrueInterest(e);

    uint256 allocationPost = allocation(id);

    assert allocationPre == allocationPost;
}

// Check that only function able to change allocation are deposit, mint, withdraw, redeem, allocation, deallocate, forceDeallocate.
rule functionsChangingAllocation(env e, method f, calldataarg args) filtered {
    f -> !f.isView &&
         f.selector != sig:deposit(uint,address).selector &&
         f.selector != sig:mint(uint,address).selector &&
         f.selector != sig:withdraw(uint,address,address).selector &&
         f.selector != sig:redeem(uint,address,address).selector &&
         f.selector != sig:allocate(address,bytes,uint).selector &&
         f.selector != sig:deallocate(address,bytes,uint).selector &&
         f.selector != sig:forceDeallocate(address,bytes,uint,address).selector
} {
    bytes32 id;
    uint256 allocationPre = allocation(id);

    f(e, args);

    uint256 allocationPost = allocation(id);

    assert allocationPost == allocationPre;
}

// Check that mint/deposit/withdraw/redeem can change an allocation only if there is a liquidity adapter set.
rule depositWithdrawChangeAllocationThroughLiquidityAdapter(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:deposit(uint,address).selector ||
         f.selector == sig:mint(uint,address).selector ||
         f.selector == sig:withdraw(uint,address,address).selector ||
         f.selector == sig:redeem(uint,address,address).selector
} {
    bytes32 id;
    uint256 allocationPre = allocation(id);

    f(e, args);

    uint256 allocationPost = allocation(id);

    assert allocationPost != allocationPre => currentContract.liquidityAdapter != 0;
}

// Check that when no liquidity adapter is set, allocation can change via *allocate functions.
rule functionsChangingAllocationWithoutLiquidityAdapter(env e, method f, calldataarg args) filtered {
    f -> !f.isView &&
         f.selector != sig:forceDeallocate(address,bytes,uint,address).selector &&
         f.selector != sig:deallocate(address,bytes,uint).selector &&
         f.selector != sig:allocate(address,bytes,uint).selector
} {
    require(currentContract.liquidityAdapter == 0, "assume no liquidity adapter");

    bytes32 id;
    uint256 allocationPre = allocation(id);

    f(e, args);

    uint256 allocationPost = allocation(id);

    assert allocationPost == allocationPre;
}
