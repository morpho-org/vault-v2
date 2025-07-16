// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

// Duration of 10 years in seconds.
definition tenYears() returns uint256 = 60 * 60 * 24 * 365 * 10;

// Check that deposit increases share value by no more than burning a single share would.
rule sharePriceBoundDeposit(env e, uint256 assets, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");
    require (currentContract.totalSupply > 0, "assume that the vault is seeded");

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant virtualSharesNotNull();

    uint256 V = currentContract.virtualShares;
    require (V <= 10^18, "require virtual shares to be lesser than or equal to 10e18");

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    deposit(e, assets, onBehalf);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert (assetsAfter + 1) * (supplyBefore + V - 1) <= (assetsBefore + 1) * (supplyAfter + V);
}

// Check that the value of shares is rounded at most one share up upon withdrawal.
rule sharePriceBoundWithdraw(env e, uint256 assets, address receiver, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");
    require (currentContract.totalSupply > 0, "assume that the vault is seeded");

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant virtualSharesNotNull();

    uint256 V = currentContract.virtualShares;
    require (V <= 10^18, "require virtual shares to be lesser than or equal to 10e18");

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    withdraw(e, assets, receiver, onBehalf);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert (assetsAfter + 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + 1 + V);
}

// Check that the user will deposit at most one extra asset.
rule sharePriceBoundMint(env e, uint256 shares, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");
    require (currentContract.totalSupply > 0, "assume that the vault is seeded");

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant virtualSharesNotNull();

    uint256 V = currentContract.virtualShares;
    require (V <= 10^18, "require virtual shares to be lesser than or equal to 10e18");

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    mint(e, shares, onBehalf);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert (assetsAfter + 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V )  + (supplyBefore + V - 1);
}

// Check that the user will be most one asset short upon redeeming.
rule sharePriceBoundRedeem(env e, uint256 shares, address receiver, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");
    require (currentContract.totalSupply > 0, "assume that the vault is seeded");

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant virtualSharesNotNull();

    uint256 V = currentContract.virtualShares;
    require (V <= 10^18, "require virtual shares to be lesser than or equal to 10e18");

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    redeem(e, shares, receiver, onBehalf);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert (assetsAfter + 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V) + (supplyBefore + V - 1);
}

// Check that loss realization is monotonic.
rule lossRealizationMonotonic(env e, address adapter, bytes data){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant virtualSharesNotNull();

    uint256 V = currentContract.virtualShares;
    require (V <= 10^18, "require virtual shares to be lesser than or equal to 10e18");

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    uint256 loss;
    (loss, _) = realizeLoss(e, adapter, data);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert loss > 0 => (assetsAfter + 1) * (supplyBefore + V) <= (assetsBefore + 1) * (supplyAfter + V);
}

// Check that share price is monotonic.
rule sharePriceMonotonic(method f, env e, calldataarg a) filtered {
    f -> f.selector != sig:realizeLoss(address, bytes).selector
} {
    require (e.block.timestamp >= currentContract.lastUpdate, "safe requirement because `lastUpdate` is growing and monotonic") ;
    require (e.block.timestamp - currentContract.lastUpdate < tenYears(), "assume the vault has been pinged less than 10 years ago");
    require (currentContract.managementFee == 0, "assume management fee to be null");
    require (currentContract.performanceFee <= Utils.maxPerformanceFee(), "safe requirement because performance fee is capped");
    require (currentContract.totalSupply > 0, "assume that the vault is seeded");

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant virtualSharesNotNull();

    uint256 V = currentContract.virtualShares;
    require (V <= 10^18, "require virtual shares to be lesser than or equal to 10e18");

    uint256 assetsBefore = currentContract._totalAssets;
    uint256 supplyBefore = currentContract.totalSupply;

    f(e, a);

    uint256 assetsAfter = currentContract._totalAssets;
    uint256 supplyAfter = currentContract.totalSupply;

    assert (assetsBefore + 1) * (supplyAfter + V) <= (assetsAfter + 1) * (supplyBefore + V);
}
