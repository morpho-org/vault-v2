// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMidnightAdapterFactory {
    /* EVENTS */

    event CreateMidnightAdapterFactory(address indexed midnight, address indexed enterGateFactory);
    event CreateMidnightAdapter(
        address indexed parentVault,
        uint256[] durations,
        bytes32 salt,
        address indexed midnightAdapter,
        bool useGateFactory
    );

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function enterGateFactory() external view returns (address);
    function midnightAdapter(address parentVault, bytes32 durationsHash, bool useGateFactory, bytes32 salt)
        external
        view
        returns (address);
    function isMidnightAdapter(address account) external view returns (bool);
    function createMidnightAdapter(address parentVault, uint256[] memory durations, bool useGateFactory, bytes32 salt)
        external
        returns (address);
}
