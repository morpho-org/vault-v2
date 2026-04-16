// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMorphoMarketV1AdapterV2Factory {
    /* EVENTS */

    event CreateMorphoMarketV1AdapterV2Factory(address indexed morpho, address indexed adaptiveCurveIrm);
    event CreateMorphoMarketV1AdapterV2(address indexed parentVault, address indexed morphoMarketV1AdapterV2);

    /* VIEW FUNCTIONS */

    function morpho() external view returns (address);
    function adaptiveCurveIrm() external view returns (address);
    function morphoMarketV1AdapterV2(address parentVault) external view returns (address);
    function isMorphoMarketV1AdapterV2(address account) external view returns (bool);

    /* NON-VIEW FUNCTIONS */

    function createMorphoMarketV1AdapterV2(address parentVault) external returns (address);
}
