// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMidnightAdapterFactory {
    /* EVENTS */

    event CreateMidnightAdapterFactory(address indexed midnight);
    event CreateMidnightAdapter(
        address indexed caller,
        address indexed parentVault,
        uint256[] durations,
        bytes32 preSalt,
        address indexed midnightAdapter
    );

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function midnightAdapter(address parentVault, bytes32 durationsHash, bytes32 salt) external view returns (address);
    function isMidnightAdapter(address account) external view returns (bool);
    function createMidnightAdapter(address parentVault, uint256[] memory durations, bytes32 preSalt)
        external
        returns (address);
}
