// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Standard as ERC20;
using ERC20Helper as ERC20Helper;
using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoVaultV1Adapter as MorphoVaultV1Adapter;

methods {
    function asset() external returns address envfree;
    function balanceOf(address) external returns uint256 envfree;
    function canReceiveShares(address) external returns bool envfree;
    function canSendShares(address) external returns bool envfree;
    function canSendAssets(address) external returns bool envfree;
    function canReceiveAssets(address) external returns bool envfree;
    function isAdapter(address) external returns bool envfree;
    function ERC20Helper.safeTransferFrom(address, address, address, uint256) external envfree;

    function _.canSendShares(address user) external => ghostCanSendShares[user] expect bool;
    function _.canReceiveShares(address user) external => ghostCanReceiveShares[user] expect bool;
    function _.canSendAssets(address user) external =>  ghostCanSendAssets[user] expect bool;
    function _.canReceiveAssets(address user) external => ghostCanReceiveAssets[user] expect bool;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
}

function summaryMorphoMarketV1Supply(MorphoMarketV1Adapter.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) returns (uint256, uint256) {
    assert shares == 0;
    assert data.length == 0;
    uint256 returnedShares;
    ERC20Helper.safeTransferFrom(marketParams.loanToken, onBehalf, MorphoMarketV1Adapter.morpho, assets);
    return (assets, returnedShares);
}

function summaryMorphoMarketV1Withdraw(MorphoMarketV1Adapter.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) returns (uint256, uint256) {
    assert shares == 0;
    uint256 returnedShares;
    ERC20Helper.safeTransferFrom(marketParams.loanToken, MorphoMarketV1Adapter.morpho, onBehalf, assets);
    return (assets, returnedShares);
}

function summaryMorphoVaultV1Deposit(uint256 assets, address receiver) returns uint256 {
    uint256 shares;
    ERC20Helper.safeTransferFrom(currentContract.asset, MorphoVaultV1Adapter, MorphoVaultV1Adapter.morphoVaultV1, assets);
    ERC20Helper.safeTransferFrom(currentContract.asset, MorphoVaultV1Adapter.morphoVaultV1, MorphoMarketV1Adapter.morpho, assets);
    return shares;
}

function summaryMorphoVaultV1Withdraw(uint256 assets, address receiver, address owner) returns uint256 {
    uint256 shares;
    ERC20Helper.safeTransferFrom(currentContract.asset, MorphoMarketV1Adapter.morpho, MorphoVaultV1Adapter.morphoVaultV1, assets);
    ERC20Helper.safeTransferFrom(currentContract.asset, MorphoVaultV1Adapter.morphoVaultV1, MorphoVaultV1Adapter, assets);
    return shares;
}

persistent ghost mapping(address => bool) ghostCanSendShares;
persistent ghost mapping(address => bool) ghostCanReceiveShares;
persistent ghost mapping(address => bool) ghostCanSendAssets;
persistent ghost mapping(address => bool) ghostCanReceiveAssets;
persistent ghost mapping(address => bool) invalidBalanceChange;

// A balance change is invalid if the balance increases when the user can't receive assets, or if it decreases when the user can't send assets.
hook Sstore ERC20.balanceOf[KEY address user] uint256 newBalance (uint256 oldBalance) {
    if (!canReceiveAssets(user) && newBalance > oldBalance) {
        invalidBalanceChange[user] = true;
    }
    if (!canSendAssets(user) && newBalance < oldBalance) {
        invalidBalanceChange[user] = true;
    }
}

// Check that the balance of shares may only decrease when a given user can't receive shares.
rule cantReceiveShares(env e, method f, calldataarg args, address user) filtered {
    f -> f.selector != sig:multicall(bytes[]).selector
}{
    require (!canReceiveShares(user), "setup gating");

    uint256 sharesBefore = balanceOf(user);

    f(e, args);

    assert balanceOf(user) <= sharesBefore;
}

// Check that the balance of shares may only increase when a given user can't send shares.
rule cantSendShares(env e, method f, calldataarg args, address user, uint256 shares) filtered {
    f -> f.selector != sig:multicall(bytes[]).selector
}{
    require (!canSendShares(user), "setup gating");

    uint256 sharesBefore = balanceOf(user);

    f(e, args);

    assert balanceOf(user) >= sharesBefore;
}

// Check that transfers initiated from the vault, assuming the vault is not reentred, may only increase the balance of a given user when he can't send, and similarly the balance may only decrease when he can't receive.
// Assume that the vault only uses market V1 and vault V1 adapters, and that those are properly deployed to point to market V1 and vault V1 respectively.
rule cantSendAssetsAndCantReceiveAssets(env e, method f, calldataarg args, address user) filtered {
    f -> f.selector != sig:multicall(bytes[]).selector
}{
    // Trick to require that all the following addresses are different.
    require(currentContract == 0x12, "ack");
    require(asset() == 0x13, "ack");

    require (user != currentContract);
    require (!currentContract.isAdapter[user]);
    require (!currentContract.isAdapter[asset()]);

    require (!invalidBalanceChange[user], "setup the ghost state");

    f(e, args);

    assert !invalidBalanceChange[user];
}
