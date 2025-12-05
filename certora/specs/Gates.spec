// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Standard as ERC20;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function balanceOf(address) external returns uint256 envfree;
    function canReceiveShares(address) external returns bool envfree;
    function canSendShares(address) external returns bool envfree;
    function canSendAssets(address) external returns bool envfree;
    function canReceiveAssets(address) external returns bool envfree;

    function _.canSendShares(address user) external => ghostCanSendShares[user] expect bool;
    function _.canReceiveShares(address user) external => ghostCanReceiveShares[user] expect bool;
    function _.canSendAssets(address user) external =>  ghostCanSendAssets[user] expect bool;
    function _.canReceiveAssets(address user) external => ghostCanReceiveAssets[user] expect bool;

    function _.transfer(address, uint256) external => DISPATCHER;
    function _.transferFrom(address, address, uint256) external => DISPATCHER;
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
rule cantReceiveShares(env e, method f, calldataarg args, address user) {
    require (!canReceiveShares(user), "setup gating");

    uint256 sharesBefore = balanceOf(user);

    f(e, args);

    assert balanceOf(user) <= sharesBefore;
}

// Check that the balance of shares may only increase when a given user can't send shares.
rule cantSendShares(env e, method f, calldataarg args, address user, uint256 shares) {
    require (!canSendShares(user), "setup gating");

    uint256 sharesBefore = balanceOf(user);

    f(e, args);

    assert balanceOf(user) >= sharesBefore;
}

// Check that transfers initiated from the vault, assuming the vault is not reentred, may only increase the balance of a given user when he can't send, and similarly the balance may only decrease when he can't receive.
// Doesn't verify that the adapters themselves don't break the gate properties.
rule cantSendAssetsAndCantReceiveAssets(env e, method f, calldataarg args, address user) {
    require (user != currentContract, "gates are not checked for the vault itself");
    require (!currentContract.isAdapter[user], "gates are not checked for the adapters");

    require (!invalidBalanceChange[user], "setup the ghost state");

    f(e, args);

    assert !invalidBalanceChange[user];
}
