// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using ERC20Mock as ERC20;
using Utils as Utils;

definition max_int256() returns int256 = (2 ^ 255) - 1;

methods {
    function isAdapter(address) external returns (bool) envfree;
    function isSentinel(address) external returns (bool) envfree;
    function Utils.decodeMarketParams(bytes) external returns (MorphoMarketV1AdapterV2.MarketParams) envfree;
    function Utils.encodeMarketParams(MorphoMarketV1AdapterV2.MarketParams) external returns (bytes) envfree;
    function Utils.id(MorphoMarketV1AdapterV2.MarketParams) external returns (MorphoMarketV1AdapterV2.Id) envfree;
    function MorphoMarketV1AdapterV2.allocation(MorphoMarketV1AdapterV2.MarketParams) external returns (uint256) envfree;
    function MorphoMarketV1AdapterV2.asset() external returns (address) envfree;
    function MorphoMarketV1AdapterV2.adaptiveCurveIrm() external returns (address) envfree;
    function MorphoMarketV1AdapterV2.supplyShares(bytes32) external returns (uint256) envfree;

    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => morphoMarketV1AdapterDeallocateWrapper(calledContract, e, data, assets, selector, sender) expect(bytes32[], int256);

    // Assume that the adapter's withdraw call succeeds.
    function _.withdraw(MorphoMarketV1AdapterV2.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) external => summaryWithdraw(marketParams, assets, shares, onBehalf, receiver) expect (uint256, uint256);

    // Transfers should not revert because market v1 sends back tokens to the adapter on withdraw.
    function ERC20.transferFrom(address, address, uint256) external returns (bool) => NONDET;

    // Assume that expectedSupplyAssets doesn't revert on market v1.
    function MorphoMarketV1AdapterV2.expectedSupplyAssets(bytes32 marketId) internal returns (uint256) => summaryExpectedSupplyAssets(marketId);
}

function summaryExpectedSupplyAssets(bytes32 marketId) returns uint256 {
    uint256 assets;
    require assets <= max_int256(), "safe because market v1 stores the total supply assets of the market in a uint128";
    return assets;
}

function summaryWithdraw(MorphoMarketV1AdapterV2.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) returns (uint256, uint256) {
    uint256 assetsWithdrawn;
    uint256 sharesWithdrawn;
    MorphoMarketV1AdapterV2.Id marketId = Utils.id(marketParams);
    require sharesWithdrawn <= MorphoMarketV1AdapterV2.supplyShares(marketId), "internal accounting of shares is less than actual held shares";
    return (assetsWithdrawn, sharesWithdrawn);
}

function morphoMarketV1AdapterDeallocateWrapper(address adapter, env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    MorphoMarketV1AdapterV2.MarketParams marketParams = Utils.decodeMarketParams(data);
    require MorphoMarketV1AdapterV2.allocation(marketParams) <= max_int256(), "see allocationIsInt256";

    bytes32[] ids;
    int256 change;
    ids, change = adapter.deallocate(e, data, assets, selector, sender);

    require forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "see distinctMarketV1Ids";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= max_int256(), "see allocationIsInt256";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0, "safe because of changeForDeallocateIsBoundedByAllocation and other ids returned have greater allocation than this/marketParams id";

    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "assume that all ids have a positive allocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change <= max_int256(), "assume that the change doesn't overflow int256 on any id";

    return (ids, change);
}

// Check that a sentinel can deallocate, assuming that:
// - the adapter has positive allocations on all ids,
// - the adapter's withdraw call succeeds,
// - expectedSupplyAssets doesn't revert
// - the change doesn't overflow int256 on any id.
rule sentinelCanDeallocate(env e, address adapter, bytes data, uint256 assets) {
    require e.block.timestamp < 2 ^ 63, "safe because it corresponds to a time very far in the future";
    require e.block.timestamp >= currentContract.lastUpdate, "safe because lastUpdate is growing and monotonic";

    MorphoMarketV1AdapterV2.MarketParams marketParams;
    require marketParams.loanToken == MorphoMarketV1AdapterV2.asset(), "setup call to have the correct loan token";
    require marketParams.irm == MorphoMarketV1AdapterV2.adaptiveCurveIrm(), "setup call to have the correct IRM";
    require data == Utils.encodeMarketParams(marketParams), "setup call to have the correct data";
    require isAdapter(adapter), "setup call to be performed on a valid adapter";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    deallocate@withrevert(e, adapter, data, assets);
    assert !lastReverted;
}
