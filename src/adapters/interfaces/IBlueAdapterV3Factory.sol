// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IBlueAdapterV3Factory {
    /* EVENTS */

    event CreateBlueAdapterV3Factory(address indexed morpho);
    event CreateBlueAdapterV3(address indexed parentVault, address indexed blueAdapterV3);

    /* VIEW FUNCTIONS */

    function morpho() external view returns (address);
    function blueAdapterV3(address parentVault) external view returns (address);
    function isBlueAdapterV3(address account) external view returns (bool);

    /* NON-VIEW FUNCTIONS */

    function createBlueAdapterV3(address parentVault) external returns (address);
}
