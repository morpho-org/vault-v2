// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// This file contains common utility functions shared across multiple adapter specification files.

// Helper function to call either allocate or deallocate based on a boolean flag.
// Used across multiple adapter specs to reduce code duplication.
function allocate_or_deallocate(bool allocate, env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    if (allocate) {
        ids, change = allocate(e, data, assets, selector, sender);
    } else {
        ids, change = deallocate(e, data, assets, selector, sender);
    }
    
    return (ids, change);
}

