// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMidnightAdapterFactory {
    /* ERRORS */

    error InvalidCreationCode();

    /* EVENTS */

    event CreateMidnightAdapterFactory(address indexed midnight);
    event CreateMidnightAdapter(
        address indexed parentVault, uint256[] durations, bytes32 salt, address indexed midnightAdapter
    );

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function midnightAdapterCreationCodeHash() external view returns (bytes32);
    function midnightAdapter(address parentVault, bytes32 durationsHash, bytes32 salt) external view returns (address);
    function isMidnightAdapter(address account) external view returns (bool);
    function createMidnightAdapter(
        address parentVault,
        uint256[] memory durations,
        bytes32 salt,
        bytes calldata creationCode
    ) external returns (address);
}
