// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function allocation(bytes32) external returns uint256 envfree;
    function owner() external returns address envfree;
    function curator() external returns address envfree;
    function isSentinel(address) external returns bool envfree;
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

    function Utils.wad() external returns uint256 envfree;
    function Utils.maxPerformanceFee() external returns uint256 envfree;
    function Utils.maxManagementFee() external returns uint256 envfree;
    function Utils.maxForceDeallocatePenalty() external returns uint256 envfree;
}

definition decreaseTimelockSelector() returns bytes4 = to_bytes4(sig:decreaseTimelock(bytes4,uint256).selector);

definition max_int256() returns int256 = (2 ^ 255) - 1;

ghost mathint sumOfBalances {
    init_state axiom sumOfBalances == 0;
}

hook Sload uint256 balance balanceOf[KEY address addr] {
    require sumOfBalances >= to_mathint(balance), "sum of balances is greater than any given balance";
}

hook Sstore balanceOf[KEY address addr] uint256 newValue (uint256 oldValue) {
    sumOfBalances = sumOfBalances - oldValue + newValue;
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

strong invariant balanceOfZero()
    balanceOf(0) == 0;

strong invariant decreaseTimelockTimelock()
    timelock(decreaseTimelockSelector()) == 0;

strong invariant totalSupplyIsSumOfBalances()
    totalSupply() == sumOfBalances;

strong invariant allocationIsInt256(bytes32 id)
    allocation(id) <= max_int256();

strong invariant registeredAdaptersAreSet()
    (forall uint256 i. i < currentContract.adapters.length => currentContract.isAdapter[currentContract.adapters[i]])
{
    preserved {
        requireInvariant adaptersUnique();
    }
}

strong invariant adaptersUnique()
    forall uint256 i. forall uint256 j. (i < j && j < currentContract.adapters.length) => currentContract.adapters[j] != currentContract.adapters[i]
{
    preserved {
        requireInvariant registeredAdaptersAreSet();
    }
}

invariant virtualSharesBounds()
    0 < currentContract.virtualShares && currentContract.virtualShares <= 10^18;
