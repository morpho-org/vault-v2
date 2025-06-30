// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IVaultV2Factory {
    /* EVENTS */

    event CreateVaultV2(address indexed owner, address indexed asset, address indexed vaultV2);

    /* FUNCTIONS */

    function isVaultV2(address account) external view returns (bool);
    function createVaultV2(address owner, address asset, bytes32 salt) external returns (address vaultV2);
}
