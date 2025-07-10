// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "MorphoMarketV1AdapterInvariant.spec";

using MorphoHarness as MorphoMarketV1;

methods {
    function asset() external returns address envfree;
    function lastUpdate() external returns uint64 envfree;
    function liquidityData() external returns bytes envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.accrueInterest(MorphoHarness.MarketParams) external => DISPATCHER(true);

    // Required to avoid explicit linking for performance reasons.
    function _.supply(MorphoHarness.MarketParams, uint256, uint256, address, bytes) external => DISPATCHER(true);
    function _.withdraw(MorphoHarness.MarketParams, uint256, uint256, address, address) external => DISPATCHER(true);

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
}

// Check balances change on deposit.
rule depositTokenChange(env e, uint256 assets, address receiver) {
    address asset = asset();

    // Trick to require that all the following addresses are different.
    require asset == 0x13;
    require e.msg.sender == 0x14;

    requireInvariant assetMatch();

    uint256 balanceMorphoMarketV1AdapterBefore = asset.balanceOf(e, MorphoMarketV1Adapter);
    uint256 balanceMorphoMarketV1Before = asset.balanceOf(e, MorphoMarketV1);
    uint256 balanceSenderBefore = asset.balanceOf(e, e.msg.sender);
    uint256 balanceVaultV2Before = asset.balanceOf(e, currentContract);

    deposit(e, assets, receiver);

    uint256 balanceMorphoMarketV1AdapterAfter = asset.balanceOf(e, MorphoMarketV1Adapter);
    uint256 balanceMorphoMarketV1After = asset.balanceOf(e, MorphoMarketV1);
    uint256 balanceSenderAfter = asset.balanceOf(e, e.msg.sender);
    uint256 balanceVaultV2After = asset.balanceOf(e, currentContract);

    assert balanceMorphoMarketV1AdapterAfter == balanceMorphoMarketV1AdapterBefore;
    assert assert_uint256(balanceMorphoMarketV1After - balanceMorphoMarketV1Before) == assets;
    assert balanceVaultV2After == balanceVaultV2Before;
    assert assert_uint256(balanceSenderBefore - balanceSenderAfter) == assets;
}

// Check balance changes on withdraw.
rule withdrawTokenChange(env e, uint256 assets, address receiver, address owner) {
    address asset = asset();

    // Trick to require that all the following addresses are different.
    require asset == 0x13;
    require receiver == 0x14;

    requireInvariant assetMatch();

    uint256 balanceMorphoMarketV1AdapterBefore = asset.balanceOf(e, MorphoMarketV1Adapter);
    uint256 balanceMorphoMarketV1Before = asset.balanceOf(e, MorphoMarketV1);
    uint256 balanceReceiverBefore = asset.balanceOf(e, receiver);
    uint256 balanceVaultV2Before = asset.balanceOf(e, currentContract);

    withdraw(e, assets, receiver, owner);

    uint256 balanceMorphoMarketV1AdapterAfter = asset.balanceOf(e, MorphoMarketV1Adapter);
    uint256 balanceMorphoMarketV1After = asset.balanceOf(e, MorphoMarketV1);
    uint256 balanceReceiverAfter = asset.balanceOf(e, receiver);
    uint256 balanceVaultV2After = asset.balanceOf(e, currentContract);

    assert balanceMorphoMarketV1AdapterAfter == balanceMorphoMarketV1AdapterBefore;

    assert balanceVaultV2Before > assets =>
        assert_uint256(balanceVaultV2Before - balanceVaultV2After) == assets;

    assert balanceVaultV2Before == 0 =>
        assert_uint256(balanceMorphoMarketV1Before - balanceMorphoMarketV1After) == assets;

    assert balanceVaultV2Before < assets =>
        assert_uint256((balanceMorphoMarketV1Before - balanceMorphoMarketV1After) + balanceVaultV2Before) == assets;

    assert assert_uint256(balanceReceiverAfter - balanceReceiverBefore) == assets;
}
