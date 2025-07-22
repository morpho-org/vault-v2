// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IOnchainVicFactory {
    /* EVENTS */

    event CreateOnchainVic(address indexed vic, address indexed vault);

    /* FUNCTIONS */

    function isOnchainVic(address) external view returns (bool);
    function onchainVic(address) external view returns (address);
    function createOnchainVic(address) external returns (address);
}
