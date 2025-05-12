// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {MorphoAdapter} from "./MorphoAdapter.sol";
import {IMorphoAdapterFactory} from "./interfaces/IMorphoAdapterFactory.sol";

contract MorphoAdapterFactory is IMorphoAdapterFactory {
    /* IMMUTABLES */

    address public immutable morpho;

    /* STORAGE */

    // vault => adapter
    /// @dev vault => adapter
    mapping(address => address) public morphoAdapter;
    mapping(address => bool) public isMorphoAdapter;

    /* FUNCTIONS */

    constructor(address _morpho) {
        morpho = _morpho;
    }

    function createMorphoAdapter(address vault) external returns (address) {
        address _morphoAdapter = address(new MorphoAdapter{salt: bytes32(0)}(vault, morpho));
        morphoAdapter[vault] = _morphoAdapter;
        isMorphoAdapter[_morphoAdapter] = true;
        emit CreateMorphoAdapter(vault, _morphoAdapter);
        return _morphoAdapter;
    }
}
