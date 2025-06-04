// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IVic} from "../../interfaces/IVic.sol";

interface IManualVic is IVic {
    /* EVENTS */

    event SetInterestPerSecond(address indexed caller, uint256 newInterestPerSecond, uint256 newDeadline);
    event ZeroInterestPerSecond(address indexed caller);
    event IncreaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond);
    event DecreaseMaxInterestPerSecond(address indexed caller, uint256 newMaxInterestPerSecond);

    /* ERRORS */

    error Unauthorized();
    error InterestPerSecondTooHigh();
    error NotIncreasing();
    error NotDecreasing();
    error DeadlineAlreadyPassed();

    /* FUNCTIONS */

    function vault() external view returns (address);
    function deadline() external view returns (uint256);
    function maxInterestPerSecond() external view returns (uint256);
    function setInterestPerSecond(uint256 newInterestPerSecond, uint256 newDeadline) external;
    function zeroInterestPerSecond() external;
    function increaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external;
    function decreaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external;
}
