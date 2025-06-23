// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMorphoBlueAdapterFactory {
    /* EVENTS */

    event CreateMorphoBlueAdapter(address indexed parentVault, address indexed morphoBlueAdapter);

    /* FUNCTIONS */

    function morphoBlueAdapter(address parentVault, address morpho) external view returns (address);
    function isMorphoBlueAdapter(address account) external view returns (bool);
    function createMorphoBlueAdapter(address parentVault, address morpho) external returns (address);
}
