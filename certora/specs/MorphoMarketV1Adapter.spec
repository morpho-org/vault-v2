// SPDX-License-Identifier: GPL-2.0-or-later

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using VaultV2 as VaultV2;

methods {
    function MorphoMarketV1Adapter.newAllocation() external returns (uint256) envfree;
    function VaultV2.allocation(bytes32 id) external returns (uint256) envfree;

    // Assume that the adapter called is MorphoMarketV1Adapter.
    function _.allocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);
}

rule allocationConsistency(method f, env e, calldataarg args, bytes32 id) {
    uint256 vaultAllocationBefore = VaultV2.allocation(id);
    uint256 adapterAllocationBefore = MorphoMarketV1Adapter.newAllocation();

    f(e, args);

    uint256 vaultAllocationAfter = VaultV2.allocation(id);
    uint256 adapterAllocationAfter = MorphoMarketV1Adapter.newAllocation();

    assert vaultAllocationBefore != vaultAllocationAfter => vaultAllocationAfter - vaultAllocationBefore == adapterAllocationAfter - adapterAllocationBefore;
}
