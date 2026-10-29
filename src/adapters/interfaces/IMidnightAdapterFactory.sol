// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.8.4;

interface IMidnightAdapterFactory {
    /* EVENTS */

    event CreateMidnightAdapterFactory(address indexed midnight, address indexed enterGateFactory);
    event CreateMidnightAdapter(
        address indexed parentVault, uint256[] durations, bytes32 salt, address indexed midnightAdapter
    );

    /* ERRORS */

    error EnterGateFactoryMidnightMismatch();

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function enterGateFactory() external view returns (address);
    function midnightAdapter(address parentVault, bytes32 durationsHash, bytes32 salt) external view returns (address);
    function isCreated(address account) external view returns (bool);
    function createMidnightAdapter(address parentVault, uint256[] memory durations, bytes32 salt)
        external
        returns (address);
}
