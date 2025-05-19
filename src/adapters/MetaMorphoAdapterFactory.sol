// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {MetaMorphoAdapter} from "./MetaMorphoAdapter.sol";
import {IMetaMorphoAdapterFactory} from "./interfaces/IMetaMorphoAdapterFactory.sol";

contract MetaMorphoAdapterFactory is IMetaMorphoAdapterFactory {
    /* STORAGE */

    mapping(address vault => mapping(address metaMorpho => address)) public metaMorphoAdapter;
    mapping(address account => bool) public isMetaMorphoAdapter;

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed MetaMorphoAdapter.
    function createMetaMorphoAdapter(address vault, address metaMorpho) external returns (address) {
        address _metaMorphoAdapter = address(new MetaMorphoAdapter{salt: bytes32(0)}(vault, metaMorpho));
        metaMorphoAdapter[vault][metaMorpho] = _metaMorphoAdapter;
        isMetaMorphoAdapter[_metaMorphoAdapter] = true;
        emit CreateMetaMorphoAdapter(vault, metaMorpho, _metaMorphoAdapter);
        return _metaMorphoAdapter;
    }
}
