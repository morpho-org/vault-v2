// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface IMorphoAdapterFactory {
    /* EVENTS */

    event CreateMorphoAdapter(address indexed morphoAdapter, address indexed vault);

    /* FUNCTIONS */

    function createMorphoAdapter(address vault) external returns (address);

    function morphoAdapter(address vault) external view returns (address);

    function isMorphoAdapter(address adapter) external view returns (bool);

    function morpho() external view returns (address);
}
