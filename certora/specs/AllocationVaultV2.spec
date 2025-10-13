// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function allocation(bytes32) external returns uint256 envfree;
}

//E RUN : https://prover.certora.com/output/7508195/f2daa878c3684e469d7a4c8cba50d159/?anonymousKey=d44f2d89bd7782a9f1e6b14443c9ae5e148dccf5

// Definition: Functions that are allowed to change allocations
definition canChangeAllocation(method f) returns bool =
    f.selector == sig:deposit(uint256,address).selector ||
    f.selector == sig:mint(uint256,address).selector ||
    f.selector == sig:withdraw(uint256,address,address).selector ||
    f.selector == sig:redeem(uint256,address,address).selector ||
    f.selector == sig:allocate(address,bytes,uint256).selector ||
    f.selector == sig:deallocate(address,bytes,uint256).selector ||
    f.selector == sig:forceDeallocate(address,bytes,uint256,address).selector;

// Check that the only functions able to change allocations are deposit, mint, withdraw, redeem, allocate, deallocate, forceDeallocate.
rule functionsChangingAllocation(env e, method f, calldataarg args) filtered {
    f -> !f.isView && !canChangeAllocation(f)
} {
    bytes32 id;
    uint256 allocationPre = allocation(id);

    f(e, args);

    assert allocation(id) == allocationPre, "Only authorized functions should change allocations";
}

// Definition: ERC4626 functions (deposit/mint/withdraw/redeem)
definition isERC4626Function(method f) returns bool =
    f.selector == sig:deposit(uint256,address).selector ||
    f.selector == sig:mint(uint256,address).selector ||
    f.selector == sig:withdraw(uint256,address,address).selector ||
    f.selector == sig:redeem(uint256,address,address).selector;

// Check that allocations change on mint/deposit/withdraw/redeem only if a liquidity adapter is set.
rule erc4626ChangeAllocationOnlyWithLiquidityAdapter(env e, method f, calldataarg args) filtered {
    f -> isERC4626Function(f)
} {
    bytes32 id;
    uint256 allocationPre = allocation(id);

    f(e, args);

    // If allocation changed, then liquidity adapter must be set
    assert allocation(id) != allocationPre => currentContract.liquidityAdapter != 0, "Allocations should only change via liquidity adapter in ERC4626 functions";
}
