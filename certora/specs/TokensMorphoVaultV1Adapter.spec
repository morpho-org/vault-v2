// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoHarness as MorphoMarketV1;
using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using MetaMorpho as MetaMorpho;

methods {
    function asset() external returns address envfree;
    function lastUpdate() external returns uint64 envfree;
    function liquidityData() external returns bytes envfree;

    function MetaMorpho.asset() external returns address envfree;

    function _.supply(MetaMorpho.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) external with (env e)
        => summarySupply(e, marketParams, assets, shares, onBehalf, data) expect (uint256, uint256) ALL;
    function _.withdraw(MetaMorpho.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) external with (env e) =>
        summaryWithdraw(e, marketParams, assets, shares, onBehalf, receiver) expect (uint256, uint256) ALL;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

    // Required to avoid explicit linking for performance reasons.
    function _.supplyShares(MorphoHarness.Id, address) external => DISPATCHER(true);
    function _.deposit(uint256, address) external => DISPATCHER(true);
    function _.withdraw(uint256, address, address) external => DISPATCHER(true);
    function _.accrueInterest(MorphoHarness.MarketParams) external => DISPATCHER(true);

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
}

function summarySupply(env e, MetaMorpho.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) returns (uint256, uint256)
{
    require (MetaMorpho.asset() == marketParams.loanToken, "safe require verified by Metamorpho's `MarketInteractions` and `ConsistentState` specifications");
    MorphoMarketV1.supply(e, marketParams, assets, shares, onBehalf, data);
    return (assets, shares);
}

function summaryWithdraw(env e, MetaMorpho.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) returns (uint256, uint256)
{
    require (MetaMorpho.asset() == marketParams.loanToken, "safe require verified by Metamorpho's `MarketInteractions` and `ConsistentState` specifications");
    MorphoMarketV1.withdraw(e, marketParams, assets, shares, onBehalf, receiver);
    return (assets, shares);
}

// Check balances change on deposit.
rule depositTokenChange(env e, uint256 assets, address receiver) {
    address asset = asset();
    require (asset == MetaMorpho.asset(), "assume that the underlying is the same across vaults");

    // Required to avoid explicit linking for performance reasons.
    require (MorphoVaultV1Adapter.morphoVaultV1 == MetaMorpho, "setup morphoVaultV1 to be MetaMorpho");

    // Trick to require that all the following addresses are different.
    require asset == 0x13;
    require e.msg.sender == 0x14;

    uint256 balanceMetaMorphoBefore = asset.balanceOf(e, MetaMorpho);
    uint256 balanceMorphoVaultV1AdapterBefore = asset.balanceOf(e, MorphoVaultV1Adapter);
    uint256 balanceMorphoMarketV1Before = asset.balanceOf(e, MorphoMarketV1);
    uint256 balanceSenderBefore = asset.balanceOf(e, e.msg.sender);
    uint256 balanceVaultV2Before = asset.balanceOf(e, currentContract);

    deposit(e, assets, receiver);

    uint256 balanceMetaMorphoAfter = asset.balanceOf(e, MetaMorpho);
    uint256 balanceMorphoVaultV1AdapterAfter = asset.balanceOf(e, MorphoVaultV1Adapter);
    uint256 balanceMorphoMarketV1After = asset.balanceOf(e, MorphoMarketV1);
    uint256 balanceSenderAfter = asset.balanceOf(e, e.msg.sender);
    uint256 balanceVaultV2After = asset.balanceOf(e, currentContract);

    assert balanceMetaMorphoAfter == balanceMetaMorphoBefore;
    assert balanceMorphoVaultV1AdapterAfter == balanceMorphoVaultV1AdapterBefore;
    assert assert_uint256(balanceMorphoMarketV1After - balanceMorphoMarketV1Before) == assets;
    assert balanceVaultV2After == balanceVaultV2Before;
    assert assert_uint256(balanceSenderBefore - balanceSenderAfter) == assets;
}

// Check balance changes on withdraw.
rule withdrawTokenChange(env e, uint256 assets, address receiver, address owner) {
    address asset = asset();
    require (asset == MetaMorpho.asset(), "assume that the underlying is the same across vaults");

    // Required to avoid explicit linking for performance reasons.
    require (MorphoVaultV1Adapter.morphoVaultV1 == MetaMorpho, "setup morphoVaultV1 to be MetaMorpho");

    // Trick to require that all the following addresses are different.
    require asset == 0x13;
    require receiver == 0x14;

    uint256 balanceMetaMorphoBefore = asset.balanceOf(e, MetaMorpho);
    uint256 balanceMorphoVaultV1AdapterBefore = asset.balanceOf(e, MorphoVaultV1Adapter);
    uint256 balanceMorphoMarketV1Before = asset.balanceOf(e, MorphoMarketV1);
    uint256 balanceReceiverBefore = asset.balanceOf(e, receiver);
    uint256 balanceVaultV2Before = asset.balanceOf(e, currentContract);

    withdraw(e, assets, receiver, owner);

    uint256 balanceMetaMorphoAfter = asset.balanceOf(e, MetaMorpho);
    uint256 balanceMorphoVaultV1AdapterAfter = asset.balanceOf(e, MorphoVaultV1Adapter);
    uint256 balanceMorphoMarketV1After = asset.balanceOf(e, MorphoMarketV1);
    uint256 balanceReceiverAfter = asset.balanceOf(e, receiver);
    uint256 balanceVaultV2After = asset.balanceOf(e, currentContract);

    assert balanceMetaMorphoAfter == balanceMetaMorphoBefore;
    assert balanceMorphoVaultV1AdapterAfter == balanceMorphoVaultV1AdapterBefore;

    assert balanceVaultV2Before > assets =>
        assert_uint256(balanceVaultV2Before - balanceVaultV2After) == assets;

    assert balanceVaultV2Before == 0 =>
        assert_uint256(balanceMorphoMarketV1Before - balanceMorphoMarketV1After) == assets;

    assert balanceVaultV2Before < assets =>
        assert_uint256((balanceMorphoMarketV1Before - balanceMorphoMarketV1After) + balanceVaultV2Before) == assets;

    assert assert_uint256(balanceReceiverAfter - balanceReceiverBefore) == assets;
}
