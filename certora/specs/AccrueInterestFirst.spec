// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function accrueInterest() internal => accrueInterestSummary();
}

persistent ghost bool accrued;

persistent ghost bool accessedBeforeAccrual;

function accrueInterestSummary() {
    accrued = true;
}

function recordAccess() {
    if (!accrued) {
        accessedBeforeAccrual = true;
    }
}

hook Sload uint128 _ _totalAssets {
    recordAccess();
}

hook Sstore _totalAssets uint128 _ {
    recordAccess();
}

hook Sload uint64 _ lastUpdate {
    recordAccess();
}

hook Sstore lastUpdate uint64 _ {
    recordAccess();
}

hook Sload uint256 _ totalSupply {
    recordAccess();
}

hook Sstore totalSupply uint256 _ {
    recordAccess();
}

hook Sload uint256 _ balanceOf[KEY address _] {
    recordAccess();
}

hook Sstore balanceOf[KEY address _] uint256 _ {
    recordAccess();
}

// firstTotalAssets is the only transient storage variable.
hook ALL_TLOAD(uint _) uint _ {
    recordAccess();
}

hook ALL_TSTORE(uint _, uint _) {
    recordAccess();
}

// Check that the variables written by accrueInterest (see AccrueInterestWrites.spec) are neither read nor written before accrueInterest in functions that accrue interest.
rule noAccessBeforeAccrueInterest(method f, env e, calldataarg data) {
    require !accrued, "setup ghost state";
    require !accessedBeforeAccrual, "setup ghost state";

    f@withrevert(e, data);

    assert accrued => !accessedBeforeAccrual;
}
