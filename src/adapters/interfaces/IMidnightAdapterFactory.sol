// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.8.4;

interface IMidnightAdapterFactory {
    /* EVENTS */

    event CreateMidnightAdapterFactory(address indexed midnight, address indexed vaultV2Factory);
    event CreateMidnightAdapter(
        address indexed caller,
        address indexed parentVault,
        uint256[] durations,
        bytes32 preSalt,
        address indexed midnightAdapter,
        address enterGateFactory
    );

    /* ERRORS */

    error NotVaultV2();

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function vaultV2Factory() external view returns (address);
    function midnightAdapter(address parentVault, bytes32 durationsHash, address enterGateFactory, bytes32 salt)
        external
        view
        returns (address);
    function isCreated(address account) external view returns (bool);
    function createMidnightAdapter(
        address parentVault,
        uint256[] memory durations,
        address enterGateFactory,
        bytes32 preSalt
    ) external returns (address);
}
