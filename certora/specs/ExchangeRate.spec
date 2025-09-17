// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

definition shares() {
    return currentContract.totalSupply + currentContract.virtualShares;
}

definition assets() {
    return currentContract._totalAssets + 1;
}

// Check that if deposit adds one more share to the user than it does, then the share price would decrease following a deposit.
rule sharePriceBoundDeposit(env e, uint256 assets, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 assetsBefore = assets();
    uint256 sharesBefore = shares();

    deposit(e, assets, onBehalf);

    assert assets() * sharesBefore <= assetsBefore * (shares() + 1);
}

// Check that if withdraw removed one less share to the user than it does, then the share price would decrease following a withdraw.
rule sharePriceBoundWithdraw(env e, uint256 assets, address receiver, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 assetsBefore = assets();
    uint256 sharesBefore = shares();

    withdraw(e, assets, receiver, onBehalf);

    assert assets() * sharesBefore <= assetsBefore * (shares() + 1);
}

// Check that if mint asks one less asset to the user than it does, then the share price would decrease following a mint.
rule sharePriceBoundMint(env e, uint256 shares, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 assetsBefore = assets();
    uint256 sharesBefore = shares();

    mint(e, shares, onBehalf);

    assert (assets() - 1) * sharesBefore <= assetsBefore * shares();
}

// Check that if redeem gave one more asset to the user than it does, then the share price would decrease following a redeem.
rule sharePriceBoundRedeem(env e, uint256 shares, address receiver, address onBehalf){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 assetsBefore = assets();
    uint256 sharesBefore = shares();

    redeem(e, shares, receiver, onBehalf);

    assert (assets() - 1) * sharesBefore <= assetsBefore * shares();
}

// Check that loss realization decreases the share price.
rule lossRealizationMonotonic(env e, address adapter, bytes data){
    require (e.block.timestamp == currentContract.lastUpdate, "assume no interest is accrued");

    uint256 assetsBefore = assets();
    uint256 sharesBefore = shares();

    accrueInterest(e);

    require (currentContract.lossRealization, "assume loss realization");

    assert assets() * sharesBefore <= assetsBefore * shares();
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

    uint256 assetsBefore = assets();
    uint256 sharesBefore = shares();

    f(e, a);

    require (!currentContract.lossRealization, "assume no loss realization");

    assert assetsBefore * shares() <= assets() * sharesBefore;
}
