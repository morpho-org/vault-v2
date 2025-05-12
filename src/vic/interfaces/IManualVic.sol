// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IVic} from "../../interfaces/IVic.sol";

interface IManualVic is IVic {
    /* EVENTS */

    event SetInterestPerSecond(address indexed caller, uint256 newInterestPerSecond);
    event IncreaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond);
    event DecreaseMaxInterestPerSecond(address caller, uint256 newMaxInterestPerSecond);

    /* ERRORS */

    error Unauthorized();
    error InterestPerSecondTooHigh();
    error NotIncreasing();
    error NotDecreasing();

    /* FUNCTIONS */

    function increaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external;
    function decreaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external;
    function setInterestPerSecond(uint256 newInterestPerSecond) external;
    function interestPerSecond(uint256, uint256) external view returns (uint256);
    function vault() external view returns (address);
    function maxInterestPerSecond() external view returns (uint256);
}
