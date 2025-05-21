// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IVic} from "../../interfaces/IVic.sol";

interface ITargetInterestVic is IVic {
    /* EVENTS */

    event SetTargetInterestPerSecond(address indexed caller, uint256 newTargetInterestPerSecond);
    event IncreaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond);
    event DecreaseMaxInterestPerSecond(address caller, uint256 newMaxInterestPerSecond);

    /* ERRORS */

    error Unauthorized();
    error TargetInterestPerSecondTooHigh();
    error NotIncreasing();
    error NotDecreasing();

    /* FUNCTIONS */

    function increaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external;
    function decreaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external;
    function setTargetInterestPerSecond(uint256 newTargetInterestPerSecond) external;
    function vault() external view returns (address);
    function maxInterestPerSecond() external view returns (uint256);
}
