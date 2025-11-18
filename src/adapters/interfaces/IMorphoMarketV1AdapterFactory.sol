// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMorphoMarketV1AdapterFactory {
    /* EVENTS */

    event CreateMorphoMarketV1Adapter(
        address indexed parentVault, address indexed morpho, address indexed morphoMarketV1Adapter
    );

    /* FUNCTIONS */

    function morphoMarketV1Adapter(address parentVault, address morpho) external view returns (address);
    function isMorphoMarketV1Adapter(address account) external view returns (bool);
    function createMorphoMarketV1Adapter(address parentVault, address morpho) external returns (address);
}
