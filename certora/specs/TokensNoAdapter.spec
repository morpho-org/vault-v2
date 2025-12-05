// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Helper as ERC20;

methods {
    function asset() external returns address envfree;

    function ERC20.balanceOf(address, address) external returns uint256 envfree;

    // Assume that the ERC20 is either ERC20NoRevert or ERC20Standard or ERC20USDT.
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
}

// Check balances change on deposit.
rule depositTokenChange(env e, uint256 assets, address receiver) {
    address asset = asset();

    // Trick to require that all the following addresses are different.
    require (currentContract == 0x10, "ack");
    require (asset == 0x11, "ack");
    require (e.msg.sender == 0x12, "ack");

    uint256 balanceSenderBefore = ERC20.balanceOf(asset, e.msg.sender);
    uint256 balanceVaultV2Before = ERC20.balanceOf(asset, currentContract);

    require (currentContract.liquidityAdapter == 0x0, "require the liquidity adapter to be unset");

    deposit(e, assets, receiver);

    uint256 balanceSenderAfter = ERC20.balanceOf(asset, e.msg.sender);
    uint256 balanceVaultV2After = ERC20.balanceOf(asset, currentContract);

    assert assert_uint256(balanceVaultV2After - balanceVaultV2Before) == assets;
    assert assert_uint256(balanceSenderBefore - balanceSenderAfter) == assets;
}

// Check balance changes on withdraw.
rule withdrawTokenChange(env e, uint256 assets, address receiver, address owner) {
    address asset = asset();

    // Trick to require that all the following addresses are different.
    require (currentContract == 0x10, "ack");
    require (asset == 0x11, "ack");
    require (receiver == 0x12, "ack");

    uint256 balanceReceiverBefore = ERC20.balanceOf(asset, receiver);
    uint256 balanceVaultV2Before = ERC20.balanceOf(asset, currentContract);

    require (currentContract.liquidityAdapter == 0x0, "require the liquidity adapter to be unset");

    withdraw(e, assets, receiver, owner);

    uint256 balanceReceiverAfter = ERC20.balanceOf(asset, receiver);
    uint256 balanceVaultV2After = ERC20.balanceOf(asset, currentContract);

    assert assert_uint256(balanceVaultV2Before - balanceVaultV2After) == assets;
    assert assert_uint256(balanceReceiverAfter - balanceReceiverBefore) == assets;
}
