// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function owner() external returns (address) envfree;
    function curator() external returns (address) envfree;
    function name() external returns (string) envfree;
    function symbol() external returns (string) envfree;
    function receiveSharesGate() external returns (address) envfree;
    function sendSharesGate() external returns (address) envfree;
    function receiveAssetsGate() external returns (address) envfree;
    function sendAssetsGate() external returns (address) envfree;
    function adapterRegistry() external returns (address) envfree;
    function isSentinel(address) external returns (bool) envfree;
    function isAllocator(address) external returns (bool) envfree;
    function adapters(uint256 index) external returns (address) envfree;
    function isAdapter(address) external returns (bool) envfree;
    function absoluteCap(bytes32 id) external returns (uint256) envfree;
    function relativeCap(bytes32 id) external returns (uint256) envfree;
    function forceDeallocatePenalty(address) external returns (uint256) envfree;
    function timelock(bytes4) external returns (uint256) envfree;
    function executableAt(bytes data) external returns (uint256) envfree;
    function abdicated(bytes4) external returns (bool) envfree;
    function performanceFee() external returns (uint96) envfree;
    function performanceFeeRecipient() external returns (address) envfree;
    function managementFee() external returns (uint96) envfree;
    function managementFeeRecipient() external returns (address) envfree;
    function maxRate() external returns (uint64) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function totalSupply() external returns (uint256) envfree;
    function allocation(bytes32 id) external returns (uint256) envfree;
    function canSendShares(address) external returns (bool) envfree;
    function canReceiveShares(address) external returns (bool) envfree;
    function canSendAssets(address) external returns (bool) envfree;
    function canReceiveAssets(address) external returns (bool) envfree;
}

definition functionIsTimelocked(method f) returns bool =
    f.selector == sig:setIsAllocator(address, bool).selector ||
    f.selector == sig:setReceiveSharesGate(address).selector ||
    f.selector == sig:setSendSharesGate(address).selector ||
    f.selector == sig:setReceiveAssetsGate(address).selector ||
    f.selector == sig:setSendAssetsGate(address).selector ||
    f.selector == sig:setAdapterRegistry(address).selector ||
    f.selector == sig:addAdapter(address).selector ||
    f.selector == sig:removeAdapter(address).selector ||
    f.selector == sig:increaseTimelock(bytes4, uint256).selector ||
    f.selector == sig:decreaseTimelock(bytes4, uint256).selector ||
    f.selector == sig:abdicate(bytes4).selector ||
    f.selector == sig:setPerformanceFee(uint256).selector ||
    f.selector == sig:setManagementFee(uint256).selector ||
    f.selector == sig:setPerformanceFeeRecipient(address).selector ||
    f.selector == sig:setManagementFeeRecipient(address).selector ||
    f.selector == sig:increaseAbsoluteCap(bytes,uint256).selector ||
    f.selector == sig:increaseRelativeCap(bytes,uint256).selector ||
    f.selector == sig:setForceDeallocatePenalty(address,uint256).selector;
