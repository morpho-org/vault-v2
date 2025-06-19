// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface ISingleMetaMorphoVicFactory {
    /* EVENTS */

    event CreateSingleMetaMorphoVic(address indexed vic, address indexed metaMorphoAdapter);

    /* FUNCTIONS */

    function isSingleMetaMorphoVic(address account) external view returns (bool);
    function singleMetaMorphoVic(address metaMorphoAdapter) external view returns (address);
    function createSingleMetaMorphoVic(address metaMorphoAdapter) external returns (address vic);
}
