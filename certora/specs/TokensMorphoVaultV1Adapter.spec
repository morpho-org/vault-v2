// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoHarness as MorphoMarketV1;
using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using MetaMorpho as MorphoVaultV1;
using ERC20Helper as ERC20;

methods {
    function _.extSloads(bytes32[]) external => NONDET DELETE;

    function asset() external returns address envfree;

    function MorphoVaultV1.asset() external returns address envfree;
    function ERC20.balanceOf(address, address) external returns uint256 envfree;

    function _.supply(MetaMorpho.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) external with (env e)
        => summarySupply(e, marketParams, assets, shares, onBehalf, data) expect (uint256, uint256) ALL;
    function _.withdraw(MetaMorpho.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) external with (env e)
        => summaryWithdraw(e, marketParams, assets, shares, onBehalf, receiver) expect (uint256, uint256) ALL;

    // Assume that the ERC20 is either ERC20NoRevert or ERC20Standard or ERC20USDT.
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

    function _.supplyShares(MorphoHarness.Id, address) external => DISPATCHER;
    function _.deposit(uint256, address) external => DISPATCHER;
    function _.withdraw(uint256, address, address) external => DISPATCHER;
    function _.accrueInterest(MorphoHarness.MarketParams) external => DISPATCHER;

    // Simplify setup, which is safe because they should change tokens balances.
    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;
    function _.canSendAssets(address) external => NONDET;
    function _.canReceiveAssets(address) external => NONDET;
}

function summarySupply(env e, MetaMorpho.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) returns (uint256, uint256)
{
    require (MorphoVaultV1.asset() == marketParams.loanToken, "safe require verified by MetaMorpho's `MarketInteractions` and `ConsistentState` specifications");
    uint256 suppliedAssets;
    uint256 suppliedShares;
    (suppliedAssets, suppliedShares) = MorphoMarketV1.supply(e, marketParams, assets, shares, onBehalf, data);
    return (suppliedAssets, suppliedShares);
}

function summaryWithdraw(env e, MetaMorpho.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) returns (uint256, uint256)
{
    require (MorphoVaultV1.asset() == marketParams.loanToken, "safe require verified by MetaMorpho's `MarketInteractions` and `ConsistentState` specifications");
    uint256 withdrawnAssets;
    uint256 withdrawnShares;
    (withdrawnAssets, withdrawnShares) = MorphoMarketV1.withdraw(e, marketParams, assets, shares, onBehalf, receiver);
    return (withdrawnAssets, withdrawnShares);
}

// Check balances change on deposit.
rule depositTokenChange(env e, uint256 assets, address receiver) {
    address asset = asset();
    require (asset == MorphoVaultV1.asset(), "assume that the underlying is the same across vaults");

    // Required to avoid explicit linking for performance reasons.
    require (MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1, "setup morphoVaultV1 to be MorphoVaultV1");

    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoVaultV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");
    require (asset == 0x13, "ack");
    require (e.msg.sender == 0x14, "ack");
    require (MorphoVaultV1 == 0x15, "ack");

    uint256 balanceMorphoVaultV1Before = ERC20.balanceOf(asset, MorphoVaultV1);
    uint256 balanceMorphoVaultV1AdapterBefore = ERC20.balanceOf(asset, MorphoVaultV1Adapter);
    uint256 balanceMorphoMarketV1Before = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceSenderBefore = ERC20.balanceOf(asset, e.msg.sender);
    uint256 balanceVaultV2Before = ERC20.balanceOf(asset, currentContract);

    // Ensure the liquidity adapter is properly linked in the conf file.
    assert currentContract.liquidityAdapter == MorphoVaultV1Adapter;

    deposit(e, assets, receiver);

    uint256 balanceMorphoVaultV1After = ERC20.balanceOf(asset, MorphoVaultV1);
    uint256 balanceMorphoVaultV1AdapterAfter = ERC20.balanceOf(asset, MorphoVaultV1Adapter);
    uint256 balanceMorphoMarketV1After = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceSenderAfter = ERC20.balanceOf(asset, e.msg.sender);
    uint256 balanceVaultV2After = ERC20.balanceOf(asset, currentContract);

    assert balanceMorphoVaultV1After == balanceMorphoVaultV1Before;
    assert balanceMorphoVaultV1AdapterAfter == balanceMorphoVaultV1AdapterBefore;
    assert assert_uint256(balanceMorphoMarketV1After - balanceMorphoMarketV1Before) == assets;
    assert balanceVaultV2After == balanceVaultV2Before;
    assert assert_uint256(balanceSenderBefore - balanceSenderAfter) == assets;
}

// Check balance changes on withdraw.
rule withdrawTokenChange(env e, uint256 assets, address receiver, address owner) {
    address asset = asset();
    require (asset == MorphoVaultV1.asset(), "assume that the underlying is the same across vaults");

    // Required to avoid explicit linking for performance reasons.
    require (MorphoVaultV1Adapter.morphoVaultV1 == MorphoVaultV1, "setup morphoVaultV1 to be MorphoVaultV1");

    // Trick to require that all the following addresses are different.
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoVaultV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");
    require (asset == 0x13, "ack");
    require (receiver == 0x14, "ack");
    require (MorphoVaultV1 == 0x15, "ack");

    uint256 balanceMorphoVaultV1Before = ERC20.balanceOf(asset, MorphoVaultV1);
    uint256 balanceMorphoVaultV1AdapterBefore = ERC20.balanceOf(asset, MorphoVaultV1Adapter);
    uint256 balanceMorphoMarketV1Before = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceReceiverBefore = ERC20.balanceOf(asset, receiver);
    uint256 balanceVaultV2Before = ERC20.balanceOf(asset, currentContract);

    // Ensure the liquidity adapter is properly linked in the conf file.
    assert currentContract.liquidityAdapter == MorphoVaultV1Adapter;

    withdraw(e, assets, receiver, owner);

    uint256 balanceMorphoVaultV1After = ERC20.balanceOf(asset, MorphoVaultV1);
    uint256 balanceMorphoVaultV1AdapterAfter = ERC20.balanceOf(asset, MorphoVaultV1Adapter);
    uint256 balanceMorphoMarketV1After = ERC20.balanceOf(asset, MorphoMarketV1);
    uint256 balanceReceiverAfter = ERC20.balanceOf(asset, receiver);
    uint256 balanceVaultV2After = ERC20.balanceOf(asset, currentContract);

    assert balanceMorphoVaultV1After == balanceMorphoVaultV1Before;
    assert balanceMorphoVaultV1AdapterAfter == balanceMorphoVaultV1AdapterBefore;

    assert balanceVaultV2Before > assets =>
            balanceMorphoMarketV1After == balanceMorphoMarketV1Before &&
        assert_uint256(balanceVaultV2Before - balanceVaultV2After) == assets;

    assert balanceVaultV2Before <= assets =>
        balanceVaultV2After == 0 &&
        assert_uint256((balanceMorphoMarketV1Before - balanceMorphoMarketV1After) + balanceVaultV2Before) == assets;

    assert assert_uint256(balanceReceiverAfter - balanceReceiverBefore) == assets;
}
