// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using ERC20Mock as ERC20;

definition max_int256() returns int256 = (2 ^ 255) - 1;

methods {
    function isAdapter(address) external returns (bool) envfree;
    function isSentinel(address) external returns (bool) envfree;
    function MorphoVaultV1Adapter.allocation() external returns (uint256) envfree;

    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => morphoVaultV1AdapterDeallocateWrapper(calledContract, e, data, assets, selector, sender) expect(bytes32[], int256);

    // Assume that the adapter's withdraw call succeeds.
    function _.withdraw(uint256 assets, address onBehalf, address receiver) external => NONDET;

    // Transfers should not revert because vault v1 sends back tokens to the adapter on withdraw.
    function ERC20.transferFrom(address, address, uint256) external returns (bool) => NONDET;

    // The function balanceOf doesn't revert on vault v1.
    function _.balanceOf(address) external => NONDET;

    // Assume that previewRedeem doesn't revert on vault v1, this implies that underlying expectedSupplyAssets calls don't revert.
    function _.previewRedeem(uint256 shares) external => summaryPreviewRedeem(shares) expect uint256;
}

function summaryPreviewRedeem(uint256 shares) returns (uint256) {
    uint256 assets;
    require assets <= max_int256(), "assume that previewRedeem returns a value bounded by max_int256";
    return assets;
}

function morphoVaultV1AdapterDeallocateWrapper(address adapter, env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    uint256 allocation = MorphoVaultV1Adapter.allocation();
    require allocation <= max_int256(), "see allocationIsInt256";

    bytes32[] ids;
    int256 change;
    ids, change = adapter.deallocate(e, data, assets, selector, sender);

    require allocation > 0, "assume that the adapter has a positive allocation";

    return (ids, change);
}

// Check that a sentinel can deallocate, assuming that:
// - the adapter has a positive allocation,
// - the adapter's withdraw call succeeds,
// - previewRedeem doesn't revert and returns a value bounded by max_int256.
rule sentinelCanDeallocate(env e, address adapter, bytes data, uint256 assets) {
    require e.block.timestamp < 2 ^ 63, "safe because it corresponds to a time very far in the future";
    require e.block.timestamp >= currentContract.lastUpdate, "safe because lastUpdate is growing and monotonic";

    require data.length == 0, "setup call to have the correct data";
    require isAdapter(adapter), "setup call to be performed on a valid adapter";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    deallocate@withrevert(e, adapter, data, assets);
    assert !lastReverted;
}
