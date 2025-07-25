// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoHarness as MorphoMarketV1;
using ERC20Helper as ERC20;

methods {
    function asset() external returns address envfree;
    function lastUpdate() external returns uint64 envfree;
    function liquidityData() external returns bytes envfree;
    function canReceiveShares(address) external returns bool envfree;
    function canSendShares(address) external returns bool envfree;
    function canSendAssets(address) external returns bool envfree;
    function canReceiveAssets(address) external returns bool envfree;
    function balanceOf(address) external returns uint256 envfree;

    function ERC20.balanceOf(address, address) external returns uint256 envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

    // Required to avoid explicit linking for performance reasons.
    function _.accrueInterest(MorphoHarness.MarketParams) external => DISPATCHER(true);
    function _.supply(MorphoHarness.MarketParams, uint256, uint256, address, bytes) external => DISPATCHER(true);
    function _.withdraw(MorphoHarness.MarketParams, uint256, uint256, address, address) external => DISPATCHER(true);

    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => NONDET;
    function _.canSendShares(address) external => PER_CALLEE_CONSTANT;
    function _.canReceiveShares(address) external => PER_CALLEE_CONSTANT;
    function _.canSendAssets(address) external => PER_CALLEE_CONSTANT;
    function _.canReceiveAssets(address) external => PER_CALLEE_CONSTANT;
}

// strong invariant cantReceiveShares(address user, uint256 shares) !canReceiveShares(user) => balanceOf(user) == shares {
//     preserved with (env e) {
//         require (MorphoMarketV1Adapter.asset == asset(), "assume that the VaultV2's underlying asset is the same as the adapter's");
//         require (MorphoMarketV1 == 0x10, "ack");
//         require (MorphoMarketV1Adapter == 0x11, "ack");
//         require (currentContract == 0x12, "ack");
//         require (asset() == 0x13, "ack");
//         require (e.msg.sender == 0x14, "ack");
//     }
// }

rule cantReceiveShares(env e, method f, calldataarg args, address user, uint256 shares) {
    require (MorphoMarketV1Adapter.asset == asset(), "assume that the VaultV2's underlying asset is the same as the adapter's");
    require (MorphoMarketV1 == 0x10, "ack");
    require (MorphoMarketV1Adapter == 0x11, "ack");
    require (currentContract == 0x12, "ack");
    require (asset() == 0x13, "ack");
    require (e.msg.sender == 0x14, "ack");

    require !canSendShares(user);
    require !canReceiveShares(user);
    require balanceOf(user) == shares;

    f(e, args);

    require !canSendShares(user);
    require !canReceiveShares(user);
    assert balanceOf(user) == shares;
}
