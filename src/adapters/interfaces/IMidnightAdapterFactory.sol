// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMidnightAdapterFactory {
    /* EVENTS */

    event CreateMidnightAdapter(address indexed parentVault, address indexed midnight, address indexed midnightAdapter);

    /* FUNCTIONS */

    function durations(uint256 index) external view returns (uint256);
    function durationsLength() external view returns (uint256);
    function midnightAdapter(address parentVault, address midnight) external view returns (address);
    function isMidnightAdapter(address account) external view returns (bool);
    function createMidnightAdapter(address parentVault, address midnight) external returns (address);
}
