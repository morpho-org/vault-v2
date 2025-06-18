// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IManualVicFactory {
    /* EVENTS */

    event CreateManualVic(address indexed vic, address indexed vault);

    /* FUNCTIONS */

    function isManualVic(address) external view returns (bool);
    function manualVic(address) external view returns (address);
    function createManualVic(address) external returns (address);
}
