// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IManualInterestControllerFactory} from "./interfaces/IManualInterestControllerFactory.sol";

import {ManualInterestController} from "./ManualInterestController.sol";

contract ManualInterestControllerFactory is IManualInterestControllerFactory {
    /*  STORAGE */

    mapping(address => bool) public isManualInterestController;

    /* EVENTS */

    event CreateManualInterestController(address indexed interestController, address indexed owner);

    /* FUNCTIONS */

    function createManualInterestController(address owner, bytes32 salt) external returns (address) {
        address interestController = address(new ManualInterestController{salt: salt}(owner));

        isManualInterestController[interestController] = true;
        emit CreateManualInterestController(interestController, owner);

        return interestController;
    }
}
