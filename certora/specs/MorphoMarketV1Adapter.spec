// SPDX-License-Identifier: GPL-2.0-or-later

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using VaultV2 as VaultV2;

methods {
    function MorphoMarketV1Adapter.allocation() external returns (uint128) envfree;
    function MorphoMarketV1Adapter.adapterId() external returns (bytes32) envfree;
    function VaultV2.allocation(bytes32 id) external returns (uint256) envfree;

    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with (env e) => summaryMorphoMarketV1AllocateOrDeallocate(e, true, data, assets, selector, sender) expect (bytes32[], int256);
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with (env e) => summaryMorphoMarketV1AllocateOrDeallocate(e, false, data, assets, selector, sender) expect (bytes32[], int256);

    // Safe assumption because the specification focuses on VaultV2 and MorphoMarketV1Adapter storage variables.
    function _.supply(MorphoMarketV1Adapter.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) external => NONDET;
    function _.withdraw(MorphoMarketV1Adapter.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

// Wrapper to ensure returned ids are distinct and assume that the adapter called is MorphoMarketV1Adapter.
function summaryMorphoMarketV1AllocateOrDeallocate(env e, bool isAllocateCall, bytes data, uint256 assets, bytes4 bs, address a) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    if (isAllocateCall) {
        ids, change = MorphoMarketV1Adapter.allocate(e, data, assets, bs, a);
    } else {
        ids, change = MorphoMarketV1Adapter.deallocate(e, data, assets, bs, a);
    }
    require forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "proven in the distinctMarketV1Ids rule";

    return (ids, change);
}

rule allocationMirrorChangesInVaultAndAdapter(method f, env e, calldataarg args, bytes32 id) {
    uint256 vaultAllocationBefore = VaultV2.allocation(id);
    uint256 adapterAllocationBefore = MorphoMarketV1Adapter.allocation();

    require vaultAllocationBefore < max_int256(), "proven in the allocationIsInt256 rule";

    f(e, args);

    uint256 vaultAllocationAfter = VaultV2.allocation(id);
    uint256 adapterAllocationAfter = MorphoMarketV1Adapter.allocation();

    assert vaultAllocationBefore != vaultAllocationAfter => vaultAllocationAfter - vaultAllocationBefore == adapterAllocationAfter - adapterAllocationBefore;
}
