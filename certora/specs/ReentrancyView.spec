// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function accrueInterestView() internal returns (uint256, uint256, uint256) with (env e) => summaryAccrueInterestView(e);

    function _.balanceOf(address) external => ignoredUintStaticcallWhenInsideAccrueInterestView() expect(uint256);
    function _.canReceiveShares(address) external => ignoredBoolStaticcallWhenInsideAccrueInterestView() expect(bool);
}

function ignoredBoolStaticcallWhenInsideAccrueInterestView() returns bool {
    ignoredStaticcall = insideAccrueInterestView;
    bool value;
    return value;
}

function ignoredUintStaticcallWhenInsideAccrueInterestView() returns uint256 {
    ignoredStaticcall = insideAccrueInterestView;
    uint256 value;
    return value;
}

function summaryAccrueInterestView(env e) returns (uint256, uint256, uint256) {
    insideAccrueInterestView = true;

    uint256 newTotalAssets;
    uint256 performanceFeeShares;
    uint256 managementFeeShares;
    (newTotalAssets, performanceFeeShares, managementFeeShares) = accrueInterestView(e);

    insideAccrueInterestView = false;

    return (newTotalAssets, performanceFeeShares, managementFeeShares);
}

persistent ghost bool insideAccrueInterestView;
persistent ghost bool ignoredStaticcall;

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
persistent ghost bool staticCallAfterSStore;

// True when at least one slot is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterSStore) {
        staticCallUnsafe = true;
    }
}

hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    if (!ignoredStaticcall && storageChanged && addr != 0x1 && addr != currentContract) {
        staticCallAfterSStore = true;
    }
    ignoredStaticcall = false;
}

// Check that there are no reentrancy unsafe calls except potentially in accrueInterestView, specifically for balanceOf on the asset and for canReceiveShares on the sharesGate.
rule reentrancyViewSafe(method f, env e, calldataarg data)
filtered {
    // forceDeallocate is a composition of deallocate and withdraw.
    f -> f.selector != sig:forceDeallocate(address, bytes, uint256, address).selector
} {
    require !ignoredStaticcall == false, "setup ghost state";
    require storageChanged == false, "setup ghost state";
    require staticCallAfterSStore == false, "setup ghost state";
    require staticCallUnsafe == false, "setup ghost state";

    f(e, data);

    assert !staticCallUnsafe;
}
