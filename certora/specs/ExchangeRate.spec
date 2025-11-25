// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

definition shares() returns mathint = currentContract.totalSupply + currentContract.virtualShares;

definition assets() returns mathint = currentContract._totalAssets + 1;

// Check that share price is increasing, except due to management fees and potentially when accruing interest (notably due to loss realization).
rule sharePriceIsIncreasing(method f, env e, calldataarg a) {
    require (e.block.timestamp >= currentContract.lastUpdate, "safe requirement because `lastUpdate` is growing and monotonic");
    requireInvariant performanceFeeBound();

    require (currentContract.totalSupply > 0, "assume that the vault is seeded");
    require (currentContract.managementFee == 0, "assume management fee to be null");
    require (currentContract.firstTotalAssets != 0, "assume that interest has been accrued");

    requireInvariant balanceOfZero();
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant virtualSharesBounds();

    mathint assetsBefore = assets();
    mathint sharesBefore = shares();

    f(e, a);

    assert assetsBefore * shares() <= assets() * sharesBefore;
}

// Check that loss realization decreases the share price.
rule lossRealizationDecreasesSharePrice(env e, address adapter, bytes data){
    mathint assetsBefore = assets();
    mathint sharesBefore = shares();

    mathint totalAssetsBefore = currentContract._totalAssets;

    accrueInterest(e);

    require (totalAssetsBefore > currentContract._totalAssets, "assume loss realization");

    assert assets() * sharesBefore <= assetsBefore * shares();
}

// Check that if deposit adds one more share to the user than it does, then the share price would decrease following a deposit.
rule optimalRoundingOnDeposit(env e, uint256 assets, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    mathint assetsBefore = assets();
    mathint sharesBefore = shares();

    deposit(e, assets, onBehalf);

    assert assets() * sharesBefore < assetsBefore * (shares() + 1);
}

// Check that if withdraw removed one less share to the user than it does, then the share price would decrease following a withdraw.
rule optimalRoundingOnWithdraw(env e, uint256 assets, address receiver, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    mathint assetsBefore = assets();
    mathint sharesBefore = shares();

    withdraw(e, assets, receiver, onBehalf);

    assert assets() * sharesBefore < assetsBefore * (shares() + 1);
}

// Check that if mint asks one less asset to the user than it does, then the share price would decrease following a mint.
rule optimalRoundingOnMint(env e, uint256 shares, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    mathint assetsBefore = assets();
    mathint sharesBefore = shares();

    mint(e, shares, onBehalf);

    assert (assets() - 1) * sharesBefore < assetsBefore * shares();
}

// Check that if redeem gave one more asset to the user than it does, then the share price would decrease following a redeem.
rule optimalRoundingOnRedeem(env e, uint256 shares, address receiver, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    mathint assetsBefore = assets();
    mathint sharesBefore = shares();

    redeem(e, shares, receiver, onBehalf);

    assert (assets() - 1) * sharesBefore < assetsBefore * shares();
}
