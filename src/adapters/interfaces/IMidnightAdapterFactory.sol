// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IMidnightAdapterFactory {
    /* EVENTS */

    event CreateMidnightAdapter(address indexed parentVault, address indexed midnight, address indexed midnightAdapter);

    /* FUNCTIONS */

    function midnightAdapter(address parentVault, address midnight) external view returns (address);
    function isMidnightAdapter(address account) external view returns (bool);
    function createMidnightAdapter(address parentVault, address midnight) external returns (address);
}
