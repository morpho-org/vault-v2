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
