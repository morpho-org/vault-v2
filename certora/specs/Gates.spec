// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Standard as ERC20;
using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoVaultV1Adapter as MorphoVaultV1Adapter;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function asset() external returns address envfree;
    function balanceOf(address) external returns uint256 envfree;
    function canReceiveShares(address) external returns bool envfree;
    function canSendShares(address) external returns bool envfree;
    function canSendAssets(address) external returns bool envfree;
    function canReceiveAssets(address) external returns bool envfree;
    function ERC20.totalSupply() external returns uint256 envfree;

    function _.canSendShares(address user) external => ghostStatusCanSendShares[user] expect bool;
    function _.canReceiveShares(address user) external => ghostStatusCanReceiveShares[user] expect bool;
    function _.canSendAssets(address user) external =>  ghostStatusCanSendAssets[user] expect bool;
    function _.canReceiveAssets(address user) external => ghostStatusCanReceiveAssets[user] expect bool;

    function _.allocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);
    function _.realizeLoss(bytes, bytes4, address) external => DISPATCHER(true);

    function _.supply(MorphoMarketV1Adapter.MarketParams, uint256, uint256, address, bytes) external => NONDET;
    function _.withdraw(MorphoMarketV1Adapter.MarketParams, uint256, uint256, address, address) external => NONDET;
    function _.deposit(uint256, address) external => NONDET;
    function _.withdraw(uint256, address, address) external => NONDET;
    function _.interestPerSecond(uint256, uint256) external => NONDET;
}

persistent ghost mapping(address => bool) ghostStatusCanSendShares;
persistent ghost mapping(address => bool) ghostStatusCanReceiveShares;
persistent ghost mapping(address => bool) ghostStatusCanSendAssets;
persistent ghost mapping(address => bool) ghostStatusCanReceiveAssets;
persistent ghost mapping(address => bool) ghostBalanceChangeAllowed;

hook Sstore ERC20.balanceOf[KEY address user] uint256 newBalance (uint256 oldBalance) {
    if (!canReceiveAssets(user)) {
        ghostBalanceChangeAllowed[user] = oldBalance >= newBalance && ghostBalanceChangeAllowed[user];
    } else if (!canSendAssets(user)) {
        ghostBalanceChangeAllowed[user] = oldBalance <= newBalance && ghostBalanceChangeAllowed[user];
    }
}

rule cantReceiveShares(env e, method f, calldataarg args, address user) filtered {
    f -> f.selector != sig:MorphoMarketV1Adapter.skim(address).selector &&
         f.selector != sig:MorphoVaultV1Adapter.skim(address).selector
}{
    require(currentContract.sharesGate != 0, "require gating to be enabled for shares");

    // Trick to require that all the following addresses are different.
    require(MorphoMarketV1Adapter == 0x10, "ack");
    require(MorphoVaultV1Adapter == 0x11, "ack");
    require(currentContract == 0x12, "ack");

    require (!canReceiveShares(user), "require that the user under scrutiny can't receive shares");

    uint256 sharesBefore = balanceOf(user);

    f(e, args);

    assert balanceOf(user) <= sharesBefore;
}

rule cantSendShares(env e, method f, calldataarg args, address user, uint256 shares)  filtered {
    f -> f.selector != sig:MorphoMarketV1Adapter.skim(address).selector &&
         f.selector != sig:MorphoVaultV1Adapter.skim(address).selector
}{
    require(currentContract.sharesGate != 0, "require gating to be enabled for shares");

    // Trick to require that all the following addresses are different.
    require(MorphoMarketV1Adapter == 0x10, "ack");
    require(MorphoVaultV1Adapter == 0x11, "ack");
    require(currentContract == 0x12, "ack");

    require (!canSendShares(user), "require that the user under scrutiny can't send shares");

    uint256 sharesBefore = balanceOf(user);

    f(e, args);

    assert balanceOf(user) >= sharesBefore;
}

rule cantReceiveAssets(env e, method f, calldataarg args, address user)  filtered {
    f -> f.selector != sig:MorphoMarketV1Adapter.skim(address).selector &&
         f.selector != sig:MorphoVaultV1Adapter.skim(address).selector
}{
    require(currentContract.receiveAssetsGate != 0, "require gating to be enabled for receiving assets");

    require(asset() == ERC20, "ack");

    // Trick to require that all the following addresses are different.
    require(MorphoMarketV1Adapter == 0x10, "ack");
    require(MorphoVaultV1Adapter == 0x11, "ack");
    require(currentContract == 0x12, "ack");
    require(asset() == 0x13, "ack");

    require (user != MorphoMarketV1Adapter && user != MorphoVaultV1Adapter && user != currentContract, "require that the vault and the adapters are allowed to receive assets");
    require (currentContract.liquidityAdapter == 0x0 || currentContract.liquidityAdapter == MorphoMarketV1Adapter || currentContract.liquidityAdapter == MorphoVaultV1Adapter, "require that the liquidity adapter is unset or a known implementation");

    require (!canReceiveAssets(user), "assume that the user under scrutiny can't receive assets");
    require (ghostBalanceChangeAllowed[user] == true, "setup the ghost state");

    f(e, args);

    assert ghostBalanceChangeAllowed[user];
}

rule cantSendAssets(env e, method f, calldataarg args, address user)  filtered {
    f -> f.selector != sig:MorphoMarketV1Adapter.skim(address).selector &&
         f.selector != sig:MorphoVaultV1Adapter.skim(address).selector
}{
    require(currentContract.sendAssetsGate != 0, "require gating to be enabled for sending assets");

    // Trick to require that all the following addresses are different.
    require(MorphoMarketV1Adapter == 0x10, "ack");
    require(MorphoVaultV1Adapter == 0x11, "ack");
    require(currentContract == 0x12, "ack");
    require(asset() == 0x13, "ack");

    require (user != MorphoMarketV1Adapter && user != MorphoVaultV1Adapter && user != currentContract, "require that the vault and the adapters are allowed to send assets");
    require (currentContract.liquidityAdapter == 0x0 || currentContract.liquidityAdapter == MorphoMarketV1Adapter || currentContract.liquidityAdapter == MorphoVaultV1Adapter, "require that the liquidity adapter is unset or a known implementation");

    require (!canSendAssets(user), "assume that the user under scrutiny can't send assets");
    require (ghostBalanceChangeAllowed[user] == true, "setup the ghost state");

    f(e, args);

    assert ghostBalanceChangeAllowed[user];
}
