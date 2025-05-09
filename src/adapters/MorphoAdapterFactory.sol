// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {MorphoAdapter} from "./MorphoAdapter.sol";

contract MorphoAdapterFactory {
    /* IMMUTABLES */

    address immutable morpho;

    /* STORAGE */

    // vault => adapter
    mapping(address => address) public morphoAdapter;
    mapping(address => bool) public isMorphoAdapter;

    /* EVENTS */

    event CreateMorphoAdapter(address indexed morphoAdapter, address indexed vault);

    /* FUNCTIONS */

    constructor(address _morpho) {
        morpho = _morpho;
    }

    function createMorphoAdapter(address vault) external returns (address) {
        address _morphoAdapter = address(new MorphoAdapter{salt: bytes32(0)}(vault, morpho));
        morphoAdapter[vault] = _morphoAdapter;
        isMorphoAdapter[_morphoAdapter] = true;
        emit CreateMorphoAdapter(_morphoAdapter, vault);
        return _morphoAdapter;
    }
}
