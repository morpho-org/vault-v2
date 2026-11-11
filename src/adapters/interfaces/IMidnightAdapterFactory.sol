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
        address indexed midnightAdapter,
        address enterGateFactory
    );

    /* ERRORS */

    error InvalidAdapterCode();

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function adapterCodeHash() external view returns (bytes32);
    function isCreated(address account) external view returns (bool);
    function createMidnightAdapter(
        address parentVault,
        uint256[] memory durations,
        address enterGateFactory,
        bytes32 preSalt,
        bytes memory code
    ) external returns (address);
}
