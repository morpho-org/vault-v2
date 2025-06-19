// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {ISingleMetaMorphoVicFactory} from "./interfaces/ISingleMetaMorphoVicFactory.sol";

import {SingleMetaMorphoVic} from "./SingleMetaMorphoVic.sol";

contract SingleMetaMorphoVicFactory is ISingleMetaMorphoVicFactory {
    /* STORAGE */

    mapping(address metaMorphoAdapter => address) public singleMetaMorphoVic;
    mapping(address account => bool) public isSingleMetaMorphoVic;

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed SingleMetaMorphoVic.
    function createSingleMetaMorphoVic(address metaMorphoAdapter) external returns (address) {
        address vic = address(new SingleMetaMorphoVic{salt: bytes32(0)}(metaMorphoAdapter));

        isSingleMetaMorphoVic[vic] = true;
        singleMetaMorphoVic[metaMorphoAdapter] = vic;
        emit CreateSingleMetaMorphoVic(vic, metaMorphoAdapter);

        return vic;
    }
}
