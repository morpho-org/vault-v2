// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMorphoMarketV2AdapterFactory {
    /* EVENTS */

    event CreateMorphoMarketV2Adapter(
        address indexed parentVault, address indexed morpho, address indexed morphoMarketV2Adapter
    );

    /* FUNCTIONS */

    function morphoMarketV2Adapter(address parentVault, address morpho) external view returns (address);
    function isMorphoMarketV2Adapter(address account) external view returns (bool);
    function createMorphoMarketV2Adapter(address parentVault, address morpho, uint32[8] memory _durations) external returns (address);
}
