// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {EventsLib} from "../libraries/EventsLib.sol";

import {IInterestController} from "../interfaces/IInterestController.sol";

contract ManualInterestController is IInterestController {
    /* IMMUTABLES */

    address public immutable owner;

    /* STORAGE */

    uint256 internal _interestPerSecond;

    /* EVENTS */

    event SetInterestPerSecond(uint256 newInterestPerSecond);

    /* ERRORS */

    error Unauthorized();

    /* FUNCTIONS */

    constructor(address _owner) {
        owner = _owner;
    }

    function setInterestPerSecond(uint256 newInterestPerSecond) public {
        require(msg.sender == owner, Unauthorized());
        _interestPerSecond = newInterestPerSecond;
        emit EventsLib.SetInterestPerSecond(newInterestPerSecond);
    }

    function interestPerSecond(uint256, uint256) external view returns (uint256) {
        return _interestPerSecond;
    }
}
