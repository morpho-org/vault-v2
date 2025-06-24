// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function owner() external returns address envfree;
    function curator() external returns address envfree;
    function isSentinel(address) external returns bool envfree;
    function isAllocator(address) external returns bool envfree;
    function lastUpdate() external returns uint64 envfree;
    function totalSupply() external returns uint256 envfree;
    function performanceFee() external returns uint96 envfree;
    function performanceFeeRecipient() external returns address envfree;
    function managementFee() external returns uint96 envfree;
    function managementFeeRecipient() external returns address envfree;
    function forceDeallocatePenalty(address) external returns uint256 envfree;
    function absoluteCap(bytes32 id) external returns uint256 envfree;
    function relativeCap(bytes32 id) external returns uint256 envfree;
    function allocation(bytes32 id) external returns uint256 envfree;
    function timelock(bytes4 selector) external returns uint256 envfree;
    function isAdapter(address adapter) external returns bool envfree;
    function balanceOf(address) external returns uint256 envfree;
    function sharesGate() external returns address envfree;
    function canReceive(address) external returns bool envfree;

    function Utils.wad() external returns uint256 envfree;
    function Utils.maxRatePerSecond() external returns uint256 envfree;
    function Utils.timelockCap() external returns uint256 envfree;
    function Utils.maxPerformanceFee() external returns uint256 envfree;
    function Utils.maxManagementFee() external returns uint256 envfree;
    function Utils.maxForceDeallocatePenalty() external returns uint256 envfree;
}

definition decreaseTimelockSelector() returns bytes4 = to_bytes4(sig:decreaseTimelock(bytes4,uint256).selector);

ghost mapping(mathint => mathint) sumOfBalances {
    init_state axiom forall mathint addr. sumOfBalances[addr] == 0;
}

ghost mapping(address => uint256) ghostBalances {
    init_state axiom forall address account. ghostBalances[account] == 0;
}

hook Sload uint256 balance balanceOf[KEY address account] {
    require ghostBalances[account] == balance;
}

hook Sstore balanceOf[KEY address account] uint256 newValue (uint256 oldValue) {
    // Update partial sum of balances, for x > to_mathint(account)
    // Track balance changes in balances.
    havoc sumOfBalances assuming
        forall mathint x. sumOfBalances@new[x] ==
            sumOfBalances@old[x] + (to_mathint(account) < x ? newValue - oldValue : 0);
    // Update ghost copy of balanceOf.
    ghostBalances[account] = newValue;
}

strong invariant sumOfBalancesStartsAtZero()
    sumOfBalances[0] == 0;

strong invariant sumOfBalancesGrowsCorrectly()
    forall address addr. sumOfBalances[to_mathint(addr) + 1] ==
        sumOfBalances[to_mathint(addr)] + ghostBalances[addr];

strong invariant sumOfBalancesMonotone()
    forall mathint i. forall mathint j. i <= j => sumOfBalances[i] <= sumOfBalances[j]
    {
        preserved {
            requireInvariant sumOfBalancesStartsAtZero();
            requireInvariant sumOfBalancesGrowsCorrectly();
        }
    }

strong invariant performanceFeeRecipient()
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipient()
    managementFee() != 0 => managementFeeRecipient() != 0;

strong invariant performanceFee()
    performanceFee() <= Utils.maxPerformanceFee();

strong invariant managementFee()
    managementFee() <= Utils.maxManagementFee();

strong invariant forceDeallocatePenalty(address adapter)
    forceDeallocatePenalty(adapter) <= Utils.maxForceDeallocatePenalty();

strong invariant zeroAddressNoBalance()
    balanceOf(0) == 0;

strong invariant timelockBounds(bytes4 selector)
    timelock(selector) <= Utils.timelockCap() || timelock(selector) == max_uint256;

strong invariant decreaseTimelockTimelock()
    timelock(decreaseTimelockSelector()) == Utils.timelockCap() || timelock(decreaseTimelockSelector()) == max_uint256;

strong invariant totalSupplyIsSumOfBalances()
    sumOfBalances[2^160] == to_mathint(totalSupply())
    {
        preserved {
            requireInvariant sumOfBalancesStartsAtZero();
            requireInvariant sumOfBalancesGrowsCorrectly();
            requireInvariant sumOfBalancesMonotone();
        }
    }

strong invariant balancesLTEqTotalSupply()
    forall address a. ghostBalances[a] <= sumOfBalances[2^160]
    {
        preserved {
            requireInvariant sumOfBalancesStartsAtZero();
            requireInvariant sumOfBalancesGrowsCorrectly();
            requireInvariant sumOfBalancesMonotone();
            requireInvariant totalSupplyIsSumOfBalances();
        }
    }

strong invariant twoBalancesLTEqTotalSupply()
    forall address a. forall address b. a != b => ghostBalances[a] + ghostBalances[b] <= sumOfBalances[2^160]
    {
        preserved {
            requireInvariant balancesLTEqTotalSupply();
            requireInvariant sumOfBalancesStartsAtZero();
            requireInvariant sumOfBalancesGrowsCorrectly();
            requireInvariant sumOfBalancesMonotone();
            requireInvariant totalSupplyIsSumOfBalances();
        }
    }
