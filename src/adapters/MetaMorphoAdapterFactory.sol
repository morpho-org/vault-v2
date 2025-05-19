// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {MetaMorphoAdapter} from "./MetaMorphoAdapter.sol";
import {IMetaMorphoAdapterFactory} from "./interfaces/IMetaMorphoAdapterFactory.sol";

contract MetaMorphoAdapterFactory is IMetaMorphoAdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address metaMorpho => address)) public metaMorphoAdapter;
    mapping(address account => bool) public isMetaMorphoAdapter;

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed MetaMorphoAdapter.
    function createMetaMorphoAdapter(address parentVault, address metaMorpho) external returns (address) {
        address _metaMorphoAdapter = address(new MetaMorphoAdapter{salt: bytes32(0)}(parentVault, metaMorpho));
        metaMorphoAdapter[parentVault][metaMorpho] = _metaMorphoAdapter;
        isMetaMorphoAdapter[_metaMorphoAdapter] = true;
        emit CreateMetaMorphoAdapter(parentVault, metaMorpho, _metaMorphoAdapter);
        return _metaMorphoAdapter;
    }
}
