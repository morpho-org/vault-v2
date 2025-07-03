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
    require currentContract.totalSupply > 0;

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();

    uint256 S = currentContract.totalSupply;
    uint256 V = currentContract.virtualShares;

    uint sharePriceBefore = convertToAssets(e, 1);
    f(e, a);
    uint256 sharePriceAfter = convertToAssets(e, 1);

    assert sharePriceBefore <= sharePriceAfter
        || f.selector == sig:realizeLoss(address, bytes).selector ;

    assert (S + V > 0 =>
            sharePriceAfter * (S + V) >= sharePriceBefore * (S + V - 1))
        || f.selector == sig:realizeLoss(address, bytes).selector ;
}
