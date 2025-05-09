// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface IERC4626AdapterFactory {
    /* EVENTS */

    event CreateERC4626Adapter(address indexed erc4626Adapter, address indexed parentVault, address indexed vault);

    /* FUNCTIONS */

    function createERC4626Adapter(address parentVault, address vault) external returns (address);

    function erc4626Adapter(address parentVault, address vault) external view returns (address);

    function isERC4626Adapter(address adapter) external view returns (bool);
}
