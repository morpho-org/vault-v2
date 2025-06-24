// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMorphoVaultV1AdapterFactory {
    /* EVENTS */

    event CreateMorphoVaultV1Adapter(
        address indexed parentVault, address indexed morphoVaultV1, address indexed morphoVaultV1Adapter
    );

    /* FUNCTIONS */

    function morphoVaultV1Adapter(address parentVault, address morphoVaultV1) external view returns (address);
    function isMorphoVaultV1Adapter(address account) external view returns (bool);
    function createMorphoVaultV1Adapter(address parentVault, address morphoVaultV1)
        external
        returns (address morphoVaultV1Adapter);
}
