// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

// Check that the price of shares is rounded at most one share down.
rule sharePriceBoundOneShareDown(method f, env e, calldataarg a) {
    require e.block.timestamp == currentContract.lastUpdate;
    require (currentContract.totalSupply > 0, "assume that the vault is seeded");

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant virtualSharesNotNull();

    uint256 V = currentContract.virtualShares;

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    f(e, a);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert  (assetsAfter + 1) * (supplyBefore + V - 1) <=  (assetsBefore + 1) * (supplyAfter + V)
        || f.selector == sig:realizeLoss(address, bytes).selector ;
}
