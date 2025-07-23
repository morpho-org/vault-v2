// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "IUtils.spec";

using Utils as Utils;

methods {
    function VaultV2.multicall(bytes[]) external => NONDET DELETE;
    function VaultV2.asset() external returns address envfree;
    function VaultV2.owner() external returns address envfree;
    function VaultV2.curator() external returns address envfree;
    function VaultV2.isSentinel(address) external returns bool envfree;
    function VaultV2.lastUpdate() external returns uint64 envfree;
    function VaultV2.totalSupply() external returns uint256 envfree;
    function VaultV2.performanceFee() external returns uint96 envfree;
    function VaultV2.performanceFeeRecipient() external returns address envfree;
    function VaultV2.managementFee() external returns uint96 envfree;
    function VaultV2.managementFeeRecipient() external returns address envfree;
    function VaultV2.forceDeallocatePenalty(address) external returns uint256 envfree;
    function VaultV2.absoluteCap(bytes32) external returns uint256 envfree;
    function VaultV2.relativeCap(bytes32) external returns uint256 envfree;
    function VaultV2.allocation(bytes32) external returns uint256 envfree;
    function VaultV2.timelock(bytes4) external returns uint256 envfree;
    function VaultV2.isAdapter(address) external returns bool envfree;
    function VaultV2.balanceOf(address) external returns uint256 envfree;
    function VaultV2.sharesGate() external returns address envfree;
    function VaultV2.canReceiveShares(address) external returns bool envfree;
}

strong invariant performanceFeeRecipient()
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipient()
    managementFee() != 0 => managementFeeRecipient() != 0;

strong invariant performanceFee()
    performanceFee() <= Utils.maxPerformanceFee();

strong invariant managementFee()
    managementFee() <= Utils.maxManagementFee();
