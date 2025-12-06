// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using MorphoHarness as MorphoMarketV1;
using ERC20Helper as ERC20;

methods {
    function asset() external returns address envfree;

    function ERC20.balanceOf(address, address) external returns uint256 envfree;

    // Assume that the ERC20 is either ERC20NoRevert or ERC20Standard or ERC20USDT.
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

    function _.accrueInterest(MorphoHarness.MarketParams) external => DISPATCHER;
    function _.supply(MorphoHarness.MarketParams, uint256, uint256, address, bytes) external => DISPATCHER;
    function _.withdraw(MorphoHarness.MarketParams, uint256, uint256, address, address) external => DISPATCHER;

    // Simplify setup, which is safe because they should not change token balances.
    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
}

// Check balances change on deposit.
rule depositTokenChange(env e, uint256 assets, address receiver) {
    address asset = asset();

    require (MorphoMarketV1AdapterV2.asset == asset, "assume that the VaultV2's underlying asset is the same as the adapter's");

    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1AdapterV2 == 0x11, "ack");
    require (currentContract == 0x12, "ack");
    require (asset == 0x13, "ack");
    require (e.msg.sender == 0x14, "ack");

    uint256 balanceMorphoMarketV1AdapterV2Before = ERC20.balanceOf(asset, MorphoMarketV1AdapterV2);
    uint256 balanceMorphoMarketV1Before = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceSenderBefore = ERC20.balanceOf(asset, e.msg.sender);
    uint256 balanceVaultV2Before = ERC20.balanceOf(asset, currentContract);

    // Ensure the liquidity adapter is properly linked in the conf file.
    assert currentContract.liquidityAdapter == MorphoMarketV1AdapterV2;

    deposit(e, assets, receiver);

    uint256 balanceMorphoMarketV1AdapterV2After = ERC20.balanceOf(asset, MorphoMarketV1AdapterV2);
    uint256 balanceMorphoMarketV1After = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceSenderAfter = ERC20.balanceOf(asset, e.msg.sender);
    uint256 balanceVaultV2After = ERC20.balanceOf(asset, currentContract);

    assert balanceMorphoMarketV1AdapterV2After == balanceMorphoMarketV1AdapterV2Before;
    assert assert_uint256(balanceMorphoMarketV1After - balanceMorphoMarketV1Before) == assets;
    assert balanceVaultV2After == balanceVaultV2Before;
    assert assert_uint256(balanceSenderBefore - balanceSenderAfter) == assets;
}

// Check balance changes on withdraw.
rule withdrawTokenChange(env e, uint256 assets, address receiver, address owner) {
    address asset = asset();

    require (MorphoMarketV1AdapterV2.asset == asset, "assume that the VaultV2's underlying asset is the same as the adapter's");

    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1AdapterV2 == 0x11, "ack");
    require (currentContract == 0x12, "ack");
    require (asset == 0x13, "ack");
    require (receiver == 0x14, "ack");

    uint256 balanceMorphoMarketV1AdapterV2Before = ERC20.balanceOf(asset, MorphoMarketV1AdapterV2);
    uint256 balanceMorphoMarketV1Before = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceReceiverBefore = ERC20.balanceOf(asset, receiver);
    uint256 balanceVaultV2Before = ERC20.balanceOf(asset, currentContract);

    // Ensure the liquidity adapter is properly linked in the conf file.
    assert currentContract.liquidityAdapter == MorphoMarketV1AdapterV2;

    withdraw(e, assets, receiver, owner);

    uint256 balanceMorphoMarketV1AdapterV2After = ERC20.balanceOf(asset, MorphoMarketV1AdapterV2);
    uint256 balanceMorphoMarketV1After = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceReceiverAfter = ERC20.balanceOf(asset, receiver);
    uint256 balanceVaultV2After = ERC20.balanceOf(asset, currentContract);

    assert balanceMorphoMarketV1AdapterV2After == balanceMorphoMarketV1AdapterV2Before;

    assert balanceVaultV2Before > assets =>
        balanceMorphoMarketV1After == balanceMorphoMarketV1Before &&
        assert_uint256(balanceVaultV2Before - balanceVaultV2After) == assets;

    assert balanceVaultV2Before <= assets =>
        balanceVaultV2After == 0 &&
        assert_uint256((balanceMorphoMarketV1Before - balanceMorphoMarketV1After) + balanceVaultV2Before) == assets;

    assert assert_uint256(balanceReceiverAfter - balanceReceiverBefore) == assets;
}
