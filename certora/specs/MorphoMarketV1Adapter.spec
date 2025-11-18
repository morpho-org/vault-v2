// SPDX-License-Identifier: GPL-2.0-or-later

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using VaultV2 as VaultV2;

methods {
    function MorphoMarketV1Adapter.allocation() external returns (uint128) envfree;
    function MorphoMarketV1Adapter.adapterId() external returns (bytes32) envfree;
    function VaultV2.allocation(bytes32 id) external returns (uint256) envfree;

    // Assume that the adapter called is MorphoMarketV1Adapter.
    function _.allocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);

    // Safe assumption because the specification focuses on VaultV2 and MorphoMarketV1Adapter storage variables.
    function _.supply(MorphoMarketV1Adapter.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) external => NONDET;
    function _.withdraw(MorphoMarketV1Adapter.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
}

invariant sameAllocationInVaultAndInAdapter()
    MorphoMarketV1Adapter.allocation() == VaultV2.allocation(MorphoMarketV1Adapter.adapterId());

rule allocationMirrorChangesInVaultAndAdapter(method f, env e, calldataarg args, bytes32 id) {
    uint256 vaultAllocationBefore = VaultV2.allocation(id);
    uint256 adapterAllocationBefore = MorphoMarketV1Adapter.allocation();

    f(e, args);

    uint256 vaultAllocationAfter = VaultV2.allocation(id);
    uint256 adapterAllocationAfter = MorphoMarketV1Adapter.allocation();

    assert vaultAllocationBefore != vaultAllocationAfter => vaultAllocationAfter - vaultAllocationBefore == adapterAllocationAfter - adapterAllocationBefore;
}
