// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

// Check that if deposit adds one share less to the user than it does, then the share price would decrease following a deposit.
rule sharePriceBoundDeposit(env e, uint256 assets, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 V = currentContract.virtualShares;

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    deposit(e, assets, onBehalf);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert (assetsAfter + 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V + 1);
}

// Check that if withdraw removed one share less to the user than it does, then the share price would decrease following a withdraw.
rule sharePriceBoundWithdraw(env e, uint256 assets, address receiver, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 V = currentContract.virtualShares;

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    withdraw(e, assets, receiver, onBehalf);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert (assetsAfter + 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V + 1);
}

// Check that mint can raise the price-per-share by no more than depositing one extra asset would.
rule sharePriceBoundMint(env e, uint256 shares, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 V = currentContract.virtualShares;
    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    mint(e, shares, onBehalf);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    // Tight inequality
    assert (assetsAfter + 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V )  + (supplyBefore + V - 1);

    assert (assetsAfter + 1 - 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V);
}

// Check that redeem can raise the price-per-share by no more than contributing one extra asset would.
rule sharePriceBoundRedeem(env e, uint256 shares, address receiver, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 V = currentContract.virtualShares;
    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    redeem(e, shares, receiver, onBehalf);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    // Tight inequality.
    assert (assetsAfter + 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V) + (supplyBefore + V - 1);

    assert (assetsAfter) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V);
}

// Check that loss realization decreases the share price.
rule lossRealizationMonotonic(env e, address adapter, bytes data){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 V = currentContract.virtualShares;
    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    accrueInterest(e);

    require (currentContract.lossRealization, "assume loss realization");
    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert (assetsAfter + 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V);
}

// Check that share price is increasing, except due to management fees or loss realization.
rule sharePriceIncreasing(method f, env e, calldataarg a) {
    require (e.block.timestamp >= currentContract.lastUpdate, "safe requirement because `lastUpdate` is growing and monotonic");
    require (currentContract.managementFee == 0, "assume management fee to be null");
    requireInvariant performanceFee();

    require (currentContract.totalSupply > 0, "assume that the vault is seeded");

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant virtualSharesBounds();

    uint256 V = currentContract.virtualShares;

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    f(e, a);

    require (!currentContract.lossRealization, "assume no loss realization");

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert (assetsBefore + 1) * (supplyAfter + V) <= (assetsAfter + 1) * (supplyBefore + V);
}
