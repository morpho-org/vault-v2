// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC4626Adapter} from "./ERC4626Adapter.sol";
import {IERC4626AdapterFactory} from "./interfaces/IERC4626AdapterFactory.sol";

contract ERC4626AdapterFactory is IERC4626AdapterFactory {
    /* STORAGE */

    /// @dev parent vault => vault => adapter
    mapping(address => mapping(address => address)) public erc4626Adapter;
    mapping(address => bool) public isERC4626Adapter;

    /* FUNCTIONS */

    function createERC4626Adapter(address parentVault, address vault) external returns (address) {
        address _erc4626Adapter = address(new ERC4626Adapter{salt: bytes32(0)}(parentVault, vault));
        erc4626Adapter[parentVault][vault] = _erc4626Adapter;
        isERC4626Adapter[_erc4626Adapter] = true;
        emit CreateERC4626Adapter(parentVault, vault, _erc4626Adapter);
        return _erc4626Adapter;
    }
}
