// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IMetaMorphoAdapterFactory {
    /* EVENTS */

    event CreateMetaMorphoAdapter(
        address indexed vault, address indexed metaMorpho, address indexed metaMorphoAdapter
    );

    /* FUNCTIONS */

    function metaMorphoAdapter(address vault, address metaMorpho) external view returns (address);
    function isMetaMorphoAdapter(address adapter) external view returns (bool);
    function createMetaMorphoAdapter(address vault, address metaMorpho) external returns (address metaMorphoAdapter);
}
