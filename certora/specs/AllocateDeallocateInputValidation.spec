// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using Utils as Utils;

// This specification checks that interaction is prevented from unknown markets.

methods {

    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryDeallocate(e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAllocate(e, data, assets, selector, sender) expect(bytes32[], int256);
}

function summaryAllocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    // Assume adapter does violates the requirement of positive absoluteCap.
    require exists uint256 i. i < ids.length && ! (currentContract.caps[ids[i]].absoluteCap > 0), "assume absolute cap is not positive";

    return (ids, change);
}

function summaryDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    // Assume adapter does violates the requirement of positive allocation.
    require exists uint256 i. i < ids.length && ! (currentContract.caps[ids[i]].allocation > 0), "assume allocation is not positive";

    return (ids, change);
}

rule allocateInputValidation(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    allocate@withrevert(e, adapter, data, assets);
    assert lastReverted;
}

rule deallocateInputValidation(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool callerIsSentinel = isSentinel(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    deallocate@withrevert(e, adapter, data, assets);
    assert lastReverted;
}
