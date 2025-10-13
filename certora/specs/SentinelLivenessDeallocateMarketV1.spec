// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using ERC20Mock as ERC20;
using Utils as Utils;

definition max_int256() returns int256 = (2 ^ 255) - 1;

methods {
    function isAdapter(address) external returns (bool) envfree;
    function isSentinel(address) external returns (bool) envfree;
    function Utils.decodeMarketParams(bytes) external returns (MorphoMarketV1Adapter.MarketParams) envfree;
    function Utils.encodeMarketParams(MorphoMarketV1Adapter.MarketParams) external returns (bytes) envfree;
    function MorphoMarketV1Adapter.allocation(MorphoMarketV1Adapter.MarketParams) external returns (uint256) envfree;
    function MorphoMarketV1Adapter.asset() external returns (address) envfree;

    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => morphoMarketV1AdapterDeallocateWrapper(calledContract, e, data, assets, selector, sender) expect(bytes32[], int256);

    // Assume that the adapter's withdraw call succeeds.
    function _.withdraw(MorphoMarketV1Adapter.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) external => NONDET;

    // Transfers should not revert because market v1 sends back tokens to the adapter on withdraw.
    function ERC20.transferFrom(address, address, uint256) external returns (bool) => NONDET;

    // Assume that expectedSupplyAssets doesn't revert on market v1.
    function _.expectedSupplyAssets(address morpho, MorphoMarketV1Adapter.MarketParams memory marketParams, address user) internal => summaryExpectedSupplyAssets(morpho, marketParams, user) expect uint256;
}

function summaryExpectedSupplyAssets(address morpho, MorphoMarketV1Adapter.MarketParams marketParams, address user) returns (uint256) {
    uint256 assets;
    require assets <= max_int256(), "assume that expectedSupplyAssets returns a value bounded by max_int256";
    return assets;
}


function morphoMarketV1AdapterDeallocateWrapper(address adapter, env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    MorphoMarketV1Adapter.MarketParams marketParams = Utils.decodeMarketParams(data);
    require MorphoMarketV1Adapter.allocation(marketParams) <= max_int256(), "see allocationIsInt256";

    bytes32[] ids;
    int256 change;
    ids, change = adapter.deallocate(e, data, assets, selector, sender);

    require forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "see distinctAdapterIds";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= max_int256(), "see allocationIsInt256";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0, "see changeForDeallocateIsBoundedByAllocation";

    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "assume that all ids have a positive allocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change <= max_int256(), "assume that the change doesn't overflow int256 on any id";

    return (ids, change);
}

// Check that a sentinel can deallocate, assuming that:
// - the adapter has positive allocations on all ids,
// - the adapter's withdraw call succeeds,
// - expectedSupplyAssets doesn't revert and returns a value bounded by max_int256.
// - the change doesn't overflow int256 on any id.
rule sentinelCanDeallocate(env e, address adapter, bytes data, uint256 assets) {
    require e.block.timestamp < 2 ^ 63, "safe because it corresponds to a time very far in the future";
    require e.block.timestamp >= currentContract.lastUpdate, "safe because lastUpdate is growing and monotonic";

    MorphoMarketV1Adapter.MarketParams marketParams;
    require marketParams.loanToken == MorphoMarketV1Adapter.asset(), "setup call to have the correct loan token";
    require data == Utils.encodeMarketParams(marketParams), "setup call to have the correct data";
    require isAdapter(adapter), "setup call to be performed on a valid adapter";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    deallocate@withrevert(e, adapter, data, assets);
    assert !lastReverted;
}
