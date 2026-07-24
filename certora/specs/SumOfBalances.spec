// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.isInRegistry(address adapter) external => ghostIsInRegistry[calledContract][adapter] expect(bool);

    function Utils.wad() external returns (uint256) envfree;
    function Utils.maxPerformanceFee() external returns (uint256) envfree;
    function Utils.maxManagementFee() external returns (uint256) envfree;
    function Utils.maxForceDeallocatePenalty() external returns (uint256) envfree;
    function Utils.maxMaxRate() external returns (uint256) envfree;
}

// For each potential adapter registry, we keep track of which adapters are in that registry, and assume that registries are all add-only.
persistent ghost mapping(address => mapping(address => bool)) ghostIsInRegistry;

// Mirror of balanceOf, summed natively with usum so each balance is bounded by the total supply.
ghost mapping(address => uint256) balanceOfGhost {
    init_state axiom forall address a. balanceOfGhost[a] == 0;
}

hook Sload uint256 balance balanceOf[KEY address addr] {
    require balanceOfGhost[addr] == balance;
}

hook Sstore balanceOf[KEY address addr] uint256 newValue (uint256 oldValue) {
    balanceOfGhost[addr] = newValue;
}

// The vault's total supply is the sum of all balances (native usum).
strong invariant totalSupplyIsSumOfBalances()
    to_mathint(totalSupply()) == (usum address a. balanceOfGhost[a]);

// Each account's balance is bounded by the total supply. usum guarantees the sum is at least any
// single balance, so this follows from totalSupplyIsSumOfBalances. Stated as a rule to keep the
// solve cheap (no per-method preservation).
rule balanceOfLeqTotalSupply(address account) {
    requireInvariant totalSupplyIsSumOfBalances();
    assert to_mathint(balanceOf(account)) <= to_mathint(totalSupply());
}
