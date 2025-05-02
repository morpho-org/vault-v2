// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {EventsLib} from "./libraries/EventsLib.sol";

import {IIRM} from "./interfaces/IIRM.sol";
import {IVaultV2} from "./interfaces/IVaultV2.sol";

contract IRM is IIRM {
    // Note that owner may be controlled by the curator, if the curator has the ability to change the IRM.
    address public immutable owner;

    uint256 internal _interestPerSecondE6;

    constructor(address _owner) {
        owner = _owner;
    }

    function setInterestPerSecondE6(uint256 newInterestPerSecondE6) public {
        require(msg.sender == owner);
        _interestPerSecondE6 = newInterestPerSecondE6;
        emit EventsLib.SetInterestPerSecondE6(newInterestPerSecondE6);
    }

    function interestPerSecondE6(uint256, uint256) external view returns (uint256) {
        return _interestPerSecondE6;
    }
}
