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

definition decreaseTimelockSelector() returns bytes4 = to_bytes4(sig:decreaseTimelock(bytes4, uint256).selector);

// For each potential adapter registry, we keep track of which adapters are in that registry, and assume that registries are all add-only.
persistent ghost mapping(address => mapping(address => bool)) ghostIsInRegistry;

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

strong invariant performanceFeeRecipientSetWhenPerformanceFeeIsSet()
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipientSetWhenManagementFeeIsSet()
    managementFee() != 0 => managementFeeRecipient() != 0;

strong invariant performanceFeeBound()
    performanceFee() <= Utils.maxPerformanceFee();

strong invariant managementFeeBound()
    managementFee() <= Utils.maxManagementFee();

strong invariant forceDeallocatePenaltyBound(address adapter)
    forceDeallocatePenalty(adapter) <= Utils.maxForceDeallocatePenalty();

strong invariant relativeCapBound(bytes32 id)
    relativeCap(id) <= 10^18;

strong invariant maxRateBound()
    maxRate() <= Utils.maxMaxRate();

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
        requireInvariant distinctAdapters();
    }
}

strong invariant distinctAdapters()
    forall uint256 i. forall uint256 j. (i < j && j < currentContract.adapters.length) => currentContract.adapters[j] != currentContract.adapters[i]
{
    preserved {
        requireInvariant registeredAdaptersAreSet();
    }
}

invariant virtualSharesBounds()
    0 < currentContract.virtualShares && currentContract.virtualShares <= 10^18;

invariant witnessForSetAdapters(address account)
    exists uint256 i. currentContract.isAdapter[account] => i < currentContract.adapters.length && currentContract.adapters[i] == account
{
    preserved {
        require currentContract.adapters.length < 2 ^ 128, "would require an unrealistic amount of computation";
    }
}

// Note: ghostIsInRegistry makes it such that adapters can't be removed from registries. Without that, the invariant doesn't hold.
strong invariant adaptersAreInRegistry(address account)
    adapterRegistry() != 0 => isAdapter(account) => ghostIsInRegistry[adapterRegistry()][account]
{
    preserved {
        requireInvariant witnessForSetAdapters(account);
    }
}
