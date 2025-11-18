// SPDX-License-Identifier: GPL-2.0-or-later

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using VaultV2 as VaultV2;

methods {
    function MorphoMarketV1Adapter.allocation() external returns (uint128) envfree;
    function VaultV2.allocation(bytes32 id) external returns (uint256) envfree;

    function VaultV2.allocate(address adapter, bytes data, uint256 assets) external with (env e) => summaryAllocate(e, adapter, data, assets);
    function VaultV2.deallocate(address adapter, bytes data, uint256 assets) external with (env e) => summaryDeallocate(e, adapter, data, assets);
}

function summaryAllocate(env e, address adapter, bytes data, uint256 assets) {
    require adapter == MorphoMarketV1Adapter, "assume that the adapter is the MorphoMarketV1Adapter";
    VaultV2.allocate(e, adapter, data, assets);
}

function summaryDeallocate(env e, address adapter, bytes data, uint256 assets) {
    require adapter == MorphoMarketV1Adapter, "assume that the adapter is the MorphoMarketV1Adapter";
    VaultV2.deallocate(e, adapter, data, assets);
}

rule allocationConsistency(method f, env e, calldataarg args, bytes32 id) {
    uint256 vaultAllocationBefore = VaultV2.allocation(id);
    uint256 adapterAllocationBefore = MorphoMarketV1Adapter.allocation();
    
    f(e, args);

    uint256 vaultAllocationAfter = VaultV2.allocation(id);
    uint256 adapterAllocationAfter = MorphoMarketV1Adapter.allocation();

    assert vaultAllocationBefore != vaultAllocationAfter => vaultAllocationBefore - vaultAllocationAfter == adapterAllocationBefore - adapterAllocationAfter;
}
