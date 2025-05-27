// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {MetaMorphoAdapter} from "./MetaMorphoAdapter.sol";
import {IMetaMorphoAdapterFactory} from "./interfaces/IMetaMorphoAdapterFactory.sol";
import {IMetaMorphoFactory} from "../../lib/metamorpho/src/interfaces/IMetaMorphoFactory.sol";

contract MetaMorphoAdapterFactory is IMetaMorphoAdapterFactory {
    /* IMMUTABLE */

    address public immutable metaMorphoFactory;

    /* STORAGE */

    mapping(address parentVault => mapping(address metaMorpho => address)) public metaMorphoAdapter;
    mapping(address account => bool) public isAdapter;

    constructor(address _metaMorphoFactory) {
        metaMorphoFactory = _metaMorphoFactory;
    }

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed MetaMorphoAdapter.
    function createMetaMorphoAdapter(address parentVault, address metaMorpho) external returns (address) {
        require(IMetaMorphoFactory(metaMorphoFactory).isMetaMorpho(metaMorpho), NotMetaMorpho());
        address _metaMorphoAdapter = address(new MetaMorphoAdapter{salt: bytes32(0)}(parentVault, metaMorpho));
        metaMorphoAdapter[parentVault][metaMorpho] = _metaMorphoAdapter;
        isAdapter[_metaMorphoAdapter] = true;
        emit CreateMetaMorphoAdapter(parentVault, metaMorpho, _metaMorphoAdapter);
        return _metaMorphoAdapter;
    }
}
