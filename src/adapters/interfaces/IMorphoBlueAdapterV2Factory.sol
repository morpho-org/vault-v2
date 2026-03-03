// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMorphoBlueAdapterV2Factory {
    /* EVENTS */

    event CreateMorphoMarketV1AdapterV2Factory(address indexed morpho, address indexed adaptiveCurveIrm);
    event CreateMorphoMarketV1AdapterV2(address indexed parentVault, address indexed morphoMarketV1AdapterV2);

    /* VIEW FUNCTIONS */

    function morpho() external view returns (address);
    function adaptiveCurveIrm() external view returns (address);
    function morphoBlueAdapterV2_71Aurmp(address parentVault) external view returns (address);
    function isMorphoBlueAdapterV2_60omp0Z(address account) external view returns (bool);

    /* NON-VIEW FUNCTIONS */

    function createMorphoBlueAdapterV2_005kLDJ(address parentVault) external returns (address);
}
