// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using MorphoHarness as Morpho;
using Utils as Utils;

methods {
    function Morpho.market(Morpho.Id) external returns (uint128, uint128, uint128, uint128, uint128, uint128) envfree;
    function Morpho.lastUpdate(Morpho.Id) external returns (uint256) envfree;
    function Morpho.supplyShares(Morpho.Id, address) external returns (uint256) envfree;
    function Morpho.totalSupplyShares(Morpho.Id) external returns (uint256) envfree;
    function Morpho.totalSupplyAssets(Morpho.Id) external returns (uint256) envfree;
    function Morpho.totalBorrowAssets(Morpho.Id) external returns (uint256) envfree;
    function MorphoMarketV1AdapterV2.asset() external returns (address) envfree;
    function MorphoMarketV1AdapterV2.adaptiveCurveIrm() external returns (address) envfree;
    function MorphoMarketV1AdapterV2.marketIdsLength() external returns (uint256) envfree;
    function MorphoMarketV1AdapterV2.marketIds(uint256) external returns (bytes32) envfree;
    function MorphoMarketV1AdapterV2.allocation(Morpho.MarketParams) external returns (uint256) envfree;
    function MorphoMarketV1AdapterV2.supplyShares(bytes32) external returns (uint256) envfree;
    function Utils.decodeMarketParams(bytes data) external returns (Morpho.MarketParams memory) envfree;
    function Utils.id(Morpho.MarketParams) external returns (Morpho.Id) envfree;
    function Utils.wrapId(bytes32) external returns (Morpho.Id) envfree;
    function Utils.unwrapId(Morpho.Id) external returns (bytes32) envfree;
    function Utils.encodeMarketParams(Morpho.MarketParams) external returns (bytes memory) envfree;
    function asset() external returns (address) envfree;
    function virtualShares() external returns (uint256) envfree;
    function lastUpdate() external returns (uint64) envfree;

    // transfers don't revert.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeERC20Lib.safeTransfer(address, address, uint256) internal => NONDET;

    function _.balanceOf(address account) external => summaryBalanceOf() expect(uint256);
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryDeallocate(e, data, assets, selector, sender) expect(bytes32[], int256);

    function _.canSendShares(address account) external => ghostCanSendShares(calledContract, account) expect(bool);
    function _.canReceiveAssets(address account) external => ghostCanReceiveAssets(calledContract, account) expect(bool);
    function _.canReceiveShares(address account) external => ghostCanReceiveShares(calledContract, account) expect(bool);
    function _.realAssets() external => summaryRealAssets() expect(uint256);
}

ghost ghostCanSendShares(address, address) returns bool;

ghost ghostCanReceiveAssets(address, address) returns bool;

ghost ghostCanReceiveShares(address, address) returns bool;

ghost ghostBalanceOf(address, address) returns uint256;

definition max_int256() returns int256 = (2 ^ 255) - 1;

function summaryBalanceOf() returns uint256 {
    uint256 balance;
    require balance < 2 ^ 128, "totalAssets is bounded by 2 ^ 128; vault balance is less than totalAssets";
    return balance;
}

function summaryRealAssets() returns uint256 {
    uint256 realAssets;
    require realAssets < 2 ^ 128, "totalAssets is bounded by 2 ^ 128; realAssets from each adater is less than totalAssets";
    return realAssets;
}

function summaryDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;
    //ids, change = MorphoMarketV1AdapterV2.deallocate(e, data, assets, selector, sender);
    require ids.length == 3, "see IdsMorphoMarketV1Adapter";

    // See distinctMarketV1Ids rule.
    require ids[0] != ids[1], "ack";
    require ids[0] != ids[2], "ack";
    require ids[1] != ids[2], "ack";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "assume that the allocation is positive";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation < 2 ^ 20 * 2 ^ 128, "market v1 fits total supply assets on 128 bits, and assume at most 2^20 markets";
    require change < 2 ^ 128, "market v1 fits total supply assets on 128 bits";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0, "see changeForAllocateOrDeallocateIsBoundedByAllocation";

    return (ids, change);
}

rule canForceDeallocateZero(env e, address adapter, bytes data, address onBehalf) {
    // IRM doesn't revert
    Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
    Morpho.Id marketId = Utils.id(marketParams);
    bytes32 id = Utils.unwrapId(marketId);

    // Adapter is registered.
    require isAdapter(adapter);

    require e.msg.value == 0;

    // Gate checks for the withdraw within forceDeallocate
    require canSendShares(onBehalf);
    require canReceiveAssets(currentContract);
    require totalSupply() + virtualShares() <= max_uint256;

    require(onBehalf != 0, "onBehalf cannot be the zero address");
    require(currentContract.lastUpdate() == e.block.timestamp, "assume interest has been accrued at the Vault level");

    forceDeallocate@withrevert(e, adapter, data, 0, onBehalf);

    assert !lastReverted;
}
