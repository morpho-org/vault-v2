// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMidnightAdapterFactory {
    /* EVENTS */

    event CreateMidnightAdapterFactory(address indexed midnight, uint256[] durations);
    event CreateMidnightAdapter(address indexed parentVault, address indexed midnightAdapter);

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function durations(uint256 index) external view returns (uint256);
    function durationsLength() external view returns (uint256);
    function midnightAdapter(address parentVault) external view returns (address);
    function isMidnightAdapter(address account) external view returns (bool);
    function createMidnightAdapter(address parentVault) external returns (address);
}
