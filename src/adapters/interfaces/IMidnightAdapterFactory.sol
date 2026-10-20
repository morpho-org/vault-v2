// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMidnightAdapterFactory {
    /* EVENTS */

    event CreateMidnightAdapterFactory(address indexed midnight);
    event CreateMidnightAdapter(
        address indexed parentVault,
        uint256[] durations,
        bytes32 salt,
        address indexed midnightAdapter,
        address indexed enterGateFactory
    );

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function midnightAdapter(address parentVault, bytes32 durationsHash, address enterGateFactory, bytes32 salt)
        external
        view
        returns (address);
    function isMidnightAdapter(address account) external view returns (bool);
    function createMidnightAdapter(
        address parentVault,
        uint256[] memory durations,
        address enterGateFactory,
        bytes32 salt
    ) external returns (address);
}
