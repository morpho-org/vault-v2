// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface ISingleMorphoVaultV1VicFactory {
    /* EVENTS */

    event CreateSingleMorphoVaultV1Vic(address indexed vic, address indexed morphoVaultV1Adapter);

    /* FUNCTIONS */

    function isSingleMorphoVaultV1Vic(address account) external view returns (bool);
    function singleMorphoVaultV1Vic(address morphoVaultV1Adapter) external view returns (address);
    function createSingleMorphoVaultV1Vic(address morphoVaultV1Adapter) external returns (address vic);
}
