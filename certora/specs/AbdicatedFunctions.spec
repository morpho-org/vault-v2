// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using ERC20Standard as ERC20;
using ERC20Helper as ERC20Helper;
using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoVaultV1Adapter as MorphoVaultV1Adapter;

methods {
    function asset() external returns (address) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function canReceiveShares(address) external returns (bool) envfree;
    function canSendShares(address) external returns (bool) envfree;
    function canSendAssets(address) external returns (bool) envfree;
    function canReceiveAssets(address) external returns (bool) envfree;
    function isAdapter(address) external returns (bool) envfree;
    function ERC20Helper.safeTransferFrom(address, address, address, uint256) external envfree;

    function _.canSendShares(address user) external => ghostCanSendShares[user] expect(bool);
    function _.canReceiveShares(address user) external => ghostCanReceiveShares[user] expect(bool);
    function _.canSendAssets(address user) external => ghostCanSendAssets[user] expect(bool);
    function _.canReceiveAssets(address user) external => ghostCanReceiveAssets[user] expect(bool);

    function _.supply(MorphoMarketV1Adapter.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) external => summaryMorphoMarketV1Supply(marketParams, assets, shares, onBehalf, data) expect(uint256, uint256) ALL;
    function _.withdraw(MorphoMarketV1Adapter.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) external => summaryMorphoMarketV1Withdraw(marketParams, assets, shares, onBehalf, receiver) expect(uint256, uint256) ALL;

    function _.allocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);
    function _.realAssets() external => DISPATCHER(true);
}

rule abdicatedFunctionsCantBeCalled(env e, method f, calldataarg args)
filtered {
    f -> f.selector == sig:setIsAllocator(address,bool).selector
        || f.selector == sig:addAdapter(address).selector
        || f.selector == sig:removeAdapter(address).selector
        || f.selector == sig:setReceiveSharesGate(address).selector
        || f.selector == sig:setSendSharesGate(address).selector
        || f.selector == sig:setReceiveAssetsGate(address).selector
        || f.selector == sig:setSendAssetsGate(address).selector
        || f.selector == sig:setAdapterRegistry(address).selector
        || f.selector == sig:increaseAbsoluteCap(bytes,uint256).selector
        || f.selector == sig:increaseRelativeCap(bytes,uint256).selector
        || f.selector == sig:setPerformanceFee(uint256).selector
        || f.selector == sig:setManagementFee(uint256).selector
        || f.selector == sig:setPerformanceFeeRecipient(address).selector
        || f.selector == sig:setManagementFeeRecipient(address).selector
        || f.selector == sig:setForceDeallocatePenalty(address,uint256).selector
        || f.selector == sig:increaseTimelock(bytes4,uint256).selector
        || f.selector == sig:decreaseTimelock(bytes4,uint256).selector
        || f.selector == sig:abdicate(bytes4).selector
}
{
    require abdicated(to_bytes4(f.selector));

    f@withrevert(e, args);

    assert lastReverted;
}
