// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMorphoMarketV1AdaptiveCurveIrmAdapterFactory {
    /* EVENTS */

    event CreateMorphoMarketV1AdaptiveCurveIrmAdapter(
        address indexed parentVault, address indexed morphoMarketV1AdaptiveCurveIrmAdapter
    );

    /* FUNCTIONS */

    function morphoMarketV1AdaptiveCurveIrmAdapter(address parentVault, address morpho)
        external
        view
        returns (address);
    function isMorphoMarketV1AdaptiveCurveIrmAdapter(address account) external view returns (bool);
    function createMorphoMarketV1AdaptiveCurveIrmAdapter(address parentVault, address morpho, address irm)
        external
        returns (address);
}
