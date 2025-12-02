// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMorphoMarketV1AdapterV2Factory {
    /* EVENTS */

    event CreateMorphoMarketV1AdapterV2Factory(address indexed adaptiveCurveIrm);

    event CreateMorphoMarketV1AdapterV2(
        address indexed parentVault,
        address indexed morpho,
        address adaptiveCurveIrm,
        address indexed morphoMarketV1AdapterV2
    );

    /* VIEW FUNCTIONS */

    function adaptiveCurveIrm() external view returns (address);

    /* NON-VIEW FUNCTIONS */

    function morphoMarketV1AdapterV2(address parentVault, address morpho) external view returns (address);
    function isMorphoMarketV1AdapterV2(address account) external view returns (bool);
    function createMorphoMarketV1AdapterV2(address parentVault, address morpho) external returns (address);
}
