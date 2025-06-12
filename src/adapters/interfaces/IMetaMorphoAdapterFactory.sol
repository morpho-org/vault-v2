// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IMetaMorphoAdapterFactory {
    /* EVENTS */

    event CreateMetaMorphoAdapter(
        address indexed parentVault, address indexed metaMorpho, address indexed metaMorphoAdapter
    );

    /* FUNCTIONS */

    function metaMorphoAdapter(address parentVault, address metaMorpho) external view returns (address);
    function isMetaMorphoAdapter(address account) external view returns (bool);
    function createMetaMorphoAdapter(address parentVault, address metaMorpho)
        external
        returns (address metaMorphoAdapter);
}
