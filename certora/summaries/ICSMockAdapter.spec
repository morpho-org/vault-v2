// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function CSMockAdapter.adapterId() external returns (bytes32) envfree;
    function CSMockAdapter.allocation() external returns (uint256) envfree;
    function CSMockAdapter.deallocate(bytes, uint, bytes4, address) external returns (bytes32[], uint) envfree;
    function CSMockAdapter.realizeLoss(bytes, bytes4, address) external returns (bytes32[], uint) envfree;
}
