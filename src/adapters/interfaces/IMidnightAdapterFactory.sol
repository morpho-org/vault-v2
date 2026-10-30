// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMidnightAdapterFactory {
    /* EVENTS */

    event CreateMidnightAdapterFactory(address indexed midnight);
    event CreateMidnightAdapter(
        address indexed parentVault, uint256[] durations, uint256 index, address indexed midnightAdapter
    );

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function midnightAdapterCount(address parentVault, bytes32 durationsHash) external view returns (uint256);
    function midnightAdapter(address parentVault, bytes32 durationsHash, uint256 index) external view returns (address);
    function isMidnightAdapter(address account) external view returns (bool);
    function createMidnightAdapter(address parentVault, uint256[] memory durations) external returns (address);
}
