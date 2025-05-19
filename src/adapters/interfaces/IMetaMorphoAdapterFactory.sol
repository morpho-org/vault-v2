// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IMetaMorphoAdapterFactory {
    /* EVENTS */

    event CreateMetaMorphoAdapter(address indexed parentVault, address indexed vault, address indexed metaMorphoAdapter);

    /* FUNCTIONS */

    function metaMorphoAdapter(address parentVault, address vault) external view returns (address);
    function isMetaMorphoAdapter(address adapter) external view returns (bool);
    function createMetaMorphoAdapter(address parentVault, address vault) external returns (address metaMorphoAdapter);
}
