// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

persistent ghost mathint sstoreCount;

persistent ghost mathint expectedSstoreCount;

persistent ghost mathint tstoreCount;

persistent ghost mathint expectedTstoreCount;

hook ALL_SSTORE(uint _, uint _) {
    sstoreCount = sstoreCount + 1;
}

hook Sstore _totalAssets uint128 _ {
    expectedSstoreCount = expectedSstoreCount + 1;
}

hook Sstore lastUpdate uint64 _ {
    expectedSstoreCount = expectedSstoreCount + 1;
}

hook Sstore totalSupply uint256 _ {
    expectedSstoreCount = expectedSstoreCount + 1;
}

hook Sstore balanceOf[KEY address _] uint256 _ {
    expectedSstoreCount = expectedSstoreCount + 1;
}

hook ALL_TSTORE(uint _, uint _) {
    tstoreCount = tstoreCount + 1;
}

hook Tstore firstTotalAssets uint256 _ {
    expectedTstoreCount = expectedTstoreCount + 1;
}

// Check that accrueInterest writes no storage variable other than _totalAssets, lastUpdate, totalSupply and balanceOf, and no transient storage variable other than firstTotalAssets.
rule accrueInterestWrites(env e) {
    require sstoreCount == 0, "setup ghost state";
    require expectedSstoreCount == 0, "setup ghost state";
    require tstoreCount == 0, "setup ghost state";
    require expectedTstoreCount == 0, "setup ghost state";

    accrueInterest(e);

    assert sstoreCount == expectedSstoreCount;
    assert tstoreCount == expectedTstoreCount;
}
