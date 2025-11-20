// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function allocation(bytes32) external returns (uint256) envfree;
}

// Check that the only functions able to change allocations are deposit, mint, withdraw, redeem, allocate, deallocate, forceDeallocate.
rule functionsChangingAllocation(env e, method f, calldataarg args)
filtered {
    f -> !f.isView &&
    f.selector != sig:deposit(uint256,address).selector &&
    f.selector != sig:mint(uint256,address).selector &&
    f.selector != sig:withdraw(uint256,address,address).selector &&
    f.selector != sig:redeem(uint256,address,address).selector &&
    f.selector != sig:allocate(address,bytes,uint256).selector &&
    f.selector != sig:deallocate(address,bytes,uint256).selector &&
    f.selector != sig:forceDeallocate(address,bytes,uint256,address).selector
}
{
    bytes32 id;
    uint256 allocationPre = allocation(id);

    f(e, args);

    assert allocation(id) == allocationPre;
}

// Check that allocations change on mint/deposit/withdraw/redeem only if a liquidity adapter is set.
rule erc4626ChangeAllocationOnlyWithLiquidityAdapter(env e, method f, calldataarg args)
filtered {
    f -> f.selector == sig:deposit(uint256,address).selector ||
    f.selector == sig:mint(uint256,address).selector ||
    f.selector == sig:withdraw(uint256,address,address).selector ||
    f.selector == sig:redeem(uint256,address,address).selector
}
{
    bytes32 id;
    uint256 allocationPre = allocation(id);

    f(e, args);

    assert allocation(id) != allocationPre => currentContract.liquidityAdapter != 0;
}
