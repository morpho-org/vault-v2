// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IManualVicFactory} from "./interfaces/IManualVicFactory.sol";

import {ManualVic} from "./ManualVic.sol";

contract ManualVicFactory is IManualVicFactory {
    /*  STORAGE */

    mapping(address => bool) public isManualVic;
    // vault => vic
    mapping(address => address) public manualVic;

    /* FUNCTIONS */

    function createManualVic(address vault) external returns (address) {
        address vic = address(new ManualVic{salt: 0}(vault));

        isManualVic[vic] = true;
        manualVic[vault] = vic;
        emit CreateManualVic(vic, vault);

        return vic;
    }
}
