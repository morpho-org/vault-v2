// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC4626Adapter} from "./ERC4626Adapter.sol";

contract ERC4626AdapterFactory {
    /* STORAGE */

    // parent vault => vault => adapter
    mapping(address => mapping(address => address)) public adapter;
    mapping(address => bool) public isAdapter;

    /* EVENTS */

    event CreateERC4626Adapter(address indexed parentVault, address indexed vault, address indexed erc4626Adapter);

    function createERC4626Adapter(address parentVault, address vault) external returns (address) {
        address erc4626Adapter = address(new ERC4626Adapter{salt: bytes32(0)}(parentVault, vault));
        adapter[parentVault][vault] = erc4626Adapter;
        isAdapter[erc4626Adapter] = true;
        emit CreateERC4626Adapter(parentVault, vault, erc4626Adapter);
        return erc4626Adapter;
    }
}
