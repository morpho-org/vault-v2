// SPDX-License-Identifier: GPL-2.0-or-later

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using VaultV2 as VaultV2;

methods {
    function MorphoMarketV1Adapter.allocation() external returns (uint128) envfree;
    function VaultV2.allocation(bytes32 id) external returns (uint256) envfree;

    // Assume that the adapter called is MorphoMarketV1Adapter.
    function _.allocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);
    function _.deallocate(bytes data, uint256 assets, bytes4, address) external => DISPATCHER(true);
}

invariant allocationConsistency(bytes32 id)
    VaultV2.allocation(id) == MorphoMarketV1Adapter.allocation();
