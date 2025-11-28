// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

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
