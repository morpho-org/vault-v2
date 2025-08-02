// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1AdaptiveCurveIrmAdapter as MorphoMarketV1AdaptiveCurveIrmAdapter;
using MorphoHarness as MorphoMarketV1;
using ERC20Helper as ERC20;

methods {
    function asset() external returns address envfree;
    function lastUpdate() external returns uint64 envfree;
    function liquidityData() external returns bytes envfree;

    function ERC20.balanceOf(address, address) external returns uint256 envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

    // Required to avoid explicit linking for performance reasons.
    function _.accrueInterest(MorphoHarness.MarketParams) external => DISPATCHER(true);
    function _.supply(MorphoHarness.MarketParams, uint256, uint256, address, bytes) external => DISPATCHER(true);
    function _.withdraw(MorphoHarness.MarketParams, uint256, uint256, address, address) external => DISPATCHER(true);

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
}

// Check balances change on deposit.
rule depositTokenChange(env e, uint256 assets, address receiver) {
    address asset = asset();

    require (MorphoMarketV1AdaptiveCurveIrmAdapter.asset == asset, "assume that the VaultV2's underlying asset is the same as the adapter's");

    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1AdaptiveCurveIrmAdapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");
    require (asset == 0x13, "ack");
    require (e.msg.sender == 0x14, "ack");

    uint256 balanceMorphoMarketV1AdaptiveCurveIrmAdapterBefore = ERC20.balanceOf(asset, MorphoMarketV1AdaptiveCurveIrmAdapter);
    uint256 balanceMorphoMarketV1Before = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceSenderBefore = ERC20.balanceOf(asset, e.msg.sender);
    uint256 balanceVaultV2Before = ERC20.balanceOf(asset, currentContract);

    // Ensure the liquidity adapter is properly linked in the conf file.
    assert currentContract.liquidityAdapter == MorphoMarketV1AdaptiveCurveIrmAdapter;

    deposit(e, assets, receiver);

    uint256 balanceMorphoMarketV1AdaptiveCurveIrmAdapterAfter = ERC20.balanceOf(asset, MorphoMarketV1AdaptiveCurveIrmAdapter);
    uint256 balanceMorphoMarketV1After = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceSenderAfter = ERC20.balanceOf(asset, e.msg.sender);
    uint256 balanceVaultV2After = ERC20.balanceOf(asset, currentContract);

    assert balanceMorphoMarketV1AdaptiveCurveIrmAdapterAfter == balanceMorphoMarketV1AdaptiveCurveIrmAdapterBefore;
    assert assert_uint256(balanceMorphoMarketV1After - balanceMorphoMarketV1Before) == assets;
    assert balanceVaultV2After == balanceVaultV2Before;
    assert assert_uint256(balanceSenderBefore - balanceSenderAfter) == assets;
}

// Check balance changes on withdraw.
rule withdrawTokenChange(env e, uint256 assets, address receiver, address owner) {
    address asset = asset();

    require (MorphoMarketV1AdaptiveCurveIrmAdapter.asset == asset, "assume that the VaultV2's underlying asset is the same as the adapter's");

    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1AdaptiveCurveIrmAdapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");
    require (asset == 0x13, "ack");
    require (receiver == 0x14, "ack");

    uint256 balanceMorphoMarketV1AdaptiveCurveIrmAdapterBefore = ERC20.balanceOf(asset, MorphoMarketV1AdaptiveCurveIrmAdapter);
    uint256 balanceMorphoMarketV1Before = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceReceiverBefore = ERC20.balanceOf(asset, receiver);
    uint256 balanceVaultV2Before = ERC20.balanceOf(asset, currentContract);

    // Ensure the liquidity adapter is properly linked in the conf file.
    assert currentContract.liquidityAdapter == MorphoMarketV1AdaptiveCurveIrmAdapter;

    withdraw(e, assets, receiver, owner);

    uint256 balanceMorphoMarketV1AdaptiveCurveIrmAdapterAfter = ERC20.balanceOf(asset, MorphoMarketV1AdaptiveCurveIrmAdapter);
    uint256 balanceMorphoMarketV1After = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceReceiverAfter = ERC20.balanceOf(asset, receiver);
    uint256 balanceVaultV2After = ERC20.balanceOf(asset, currentContract);

    assert balanceMorphoMarketV1AdaptiveCurveIrmAdapterAfter == balanceMorphoMarketV1AdaptiveCurveIrmAdapterBefore;

    assert balanceVaultV2Before > assets =>
        balanceMorphoMarketV1After == balanceMorphoMarketV1Before &&
        assert_uint256(balanceVaultV2Before - balanceVaultV2After) == assets;

    assert balanceVaultV2Before <= assets =>
        balanceVaultV2After == 0 &&
        assert_uint256((balanceMorphoMarketV1Before - balanceMorphoMarketV1After) + balanceVaultV2Before) == assets;

    assert assert_uint256(balanceReceiverAfter - balanceReceiverBefore) == assets;
}
