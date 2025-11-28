// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

function allocateOrDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    bool isAllocate;
    if (isAllocate) {
        ids, change = allocate(e, data, assets, selector, sender);
    } else {
        ids, change = deallocate(e, data, assets, selector, sender);
    }

    return (ids, change);
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
