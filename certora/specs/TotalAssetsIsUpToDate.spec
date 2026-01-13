// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function accrueInterest() internal => summaryAccrueInterest();
}

persistent ghost bool totalAssetsUpdated;

persistent ghost bool totalAssetsReadBeforeUpdated;

function summaryAccrueInterest() {
    totalAssetsUpdated = true;
}

hook Sload uint128 readValue _totalAssets {
    if (!totalAssetsUpdated) {
        totalAssetsReadBeforeUpdated = true;
    }
}

// Check that, except in accrueInterest, the variable _totalAssets is never read before being updated.
rule totalAssetsIsUpToDate(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    require !totalAssetsUpdated, "setup the ghost state";
    require !totalAssetsReadBeforeUpdated, "setup the ghost state";

    f(e, args);

    assert !totalAssetsReadBeforeUpdated;
}
