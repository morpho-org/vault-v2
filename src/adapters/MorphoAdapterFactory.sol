// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {MorphoAdapter} from "./MorphoAdapter.sol";

contract MorphoAdapterFactory {
    /* IMMUTABLES */

    address immutable morpho;

    /* STORAGE */

    // vault => adapter
    mapping(address => address) public adapter;
    mapping(address => bool) public isAdapter;

    /* EVENTS */

    event CreateMorphoAdapter(address indexed vault, address indexed morphoAdapter);

    /* FUNCTIONS */

    constructor(address _morpho) {
        morpho = _morpho;
    }

    function createMorphoAdapter(address vault) external returns (address) {
        address morphoAdapter = address(new MorphoAdapter{salt: bytes32(0)}(vault, morpho));
        adapter[vault] = morphoAdapter;
        isAdapter[morphoAdapter] = true;
        emit CreateMorphoAdapter(vault, morphoAdapter);
        return morphoAdapter;
    }
}
