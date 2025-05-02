// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {BlueAdapter} from "./BlueAdapter.sol";

contract BlueAdapterFactory {
    /* IMMUTABLES */

    address immutable morpho;

    /* STORAGE */

    // vault => adapter
    mapping(address => address) public adapter;
    mapping(address => bool) public isAdapter;

    /* EVENTS */

    event CreateBlueAdapter(address indexed vault, address indexed blueAdapter);

    /* FUNCTIONS */

    constructor(address _morpho) {
        morpho = _morpho;
    }

    function createBlueAdapter(address vault) external returns (address) {
        address blueAdapter = address(new BlueAdapter{salt: bytes32(0)}(vault, morpho));
        adapter[vault] = blueAdapter;
        isAdapter[blueAdapter] = true;
        emit CreateBlueAdapter(vault, blueAdapter);
        return blueAdapter;
    }
}
