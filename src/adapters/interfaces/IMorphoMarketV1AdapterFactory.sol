// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMorphoMarketV1AdapterFactory {
    /* EVENTS */

    event CreateMorphoMarketV1AdapterFactory(address indexed adaptiveCurveIrm);

    event CreateMorphoMarketV1Adapter(
        address indexed parentVault,
        address indexed morpho,
        address adaptiveCurveIrm,
        address indexed morphoMarketV1Adapter
    );

    /* VIEW FUNCTIONS */

    function adaptiveCurveIrm() external view returns (address);

    /* NON-VIEW FUNCTIONS */

    function morphoMarketV1Adapter(address parentVault, address morpho) external view returns (address);
    function isMorphoMarketV1Adapter(address account) external view returns (bool);
    function createMorphoMarketV1Adapter(address parentVault, address morpho) external returns (address);
}
