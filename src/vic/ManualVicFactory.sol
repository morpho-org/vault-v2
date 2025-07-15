// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IManualVicFactory} from "./interfaces/IManualVicFactory.sol";

import {ManualVic} from "./ManualVic.sol";

contract ManualVicFactory is IManualVicFactory {
    /*  STORAGE */

    mapping(address vault => address) public manualVic;
    mapping(address account => bool) public isManualVic;

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed ManualVic.
    function createManualVic(address vault) external returns (address) {
        address vic = address(new ManualVic{salt: bytes32(0)}(vault));

        isManualVic[vic] = true;
        manualVic[vault] = vic;
        emit CreateManualVic(vic, vault);

        return vic;
    }
}
