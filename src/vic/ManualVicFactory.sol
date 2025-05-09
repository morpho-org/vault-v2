// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IManualVicFactory} from "./interfaces/IManualVicFactory.sol";

import {ManualVic} from "./ManualVic.sol";

contract ManualVicFactory is IManualVicFactory {
    /*  STORAGE */

    mapping(address => bool) public isManualVic;

    /* EVENTS */

    event CreateManualVic(address indexed vic, address indexed owner);

    /* FUNCTIONS */

    function createManualVic(address owner, bytes32 salt) external returns (address) {
        address vic = address(new ManualVic{salt: salt}(owner));

        isManualVic[vic] = true;
        emit CreateManualVic(vic, owner);

        return vic;
    }
}
