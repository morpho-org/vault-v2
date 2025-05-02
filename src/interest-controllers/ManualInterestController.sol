// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {EventsLib} from "../libraries/EventsLib.sol";

import {IInterestController} from "../interfaces/IInterestController.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";

contract ManualInterestController is IInterestController {
    // Note that owner may be controlled by the curator, if the curator has the ability to change the
    // InterestController.
    address public immutable owner;

    uint256 internal _interestPerSecond;

    constructor(address _owner) {
        owner = _owner;
    }

    function setInterestPerSecond(uint256 newInterestPerSecond) public {
        require(msg.sender == owner);
        _interestPerSecond = newInterestPerSecond;
        emit EventsLib.SetInterestPerSecond(newInterestPerSecond);
    }

    function interestPerSecond(uint256, uint256) external view returns (uint256) {
        return _interestPerSecond;
    }
}
