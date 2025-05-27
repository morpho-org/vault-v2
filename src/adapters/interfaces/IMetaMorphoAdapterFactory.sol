// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IAdapterFactory} from "../../interfaces/IAdapterFactory.sol";

interface IMetaMorphoAdapterFactory is IAdapterFactory {
    /* EVENTS */

    event CreateMetaMorphoAdapter(
        address indexed parentVault, address indexed vault, address indexed metaMorphoAdapter
    );

    /* ERRORS */
    error NotMetaMorpho();

    /* FUNCTIONS */

    function metaMorphoAdapter(address parentVault, address vault) external view returns (address);
    function createMetaMorphoAdapter(address parentVault, address vault) external returns (address metaMorphoAdapter);
}
