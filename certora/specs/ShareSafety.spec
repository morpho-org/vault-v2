// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

methods {
    function _.interestPerSecond(uint256, uint256) external =>
        nondetUintSummary() expect uint256;
}

function nondetUintSummary() returns uint256 {
    uint256 value;
    return value;
}

rule sharePriceDoesntChange(method f, env e, calldataarg a) {
    require e.block.timestamp == currentContract.lastUpdate;
    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();

    uint sharePriceBefore = convertToAssets(e, 1);
    f(e, a);
    assert sharePriceBefore == convertToAssets(e, 1)
        || f.selector == sig:realizeLoss(address, bytes).selector ;
}
