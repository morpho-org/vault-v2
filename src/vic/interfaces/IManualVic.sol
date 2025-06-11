// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IVic} from "../../interfaces/IVic.sol";

interface IManualVic is IVic {
    /* EVENTS */

    event SetInterestPerSecondAndDeadline(address indexed caller, uint256 newInterestPerSecond, uint256 newDeadline);
    event ZeroInterestPerSecond(address indexed caller);
    event SetMaxInterestPerSecond(uint256 newMaxInterestPerSecond);
    event ZeroMaxInterestPerSecond(address indexed caller);

    /* ERRORS */

    error Unauthorized();
    error InterestPerSecondTooHigh();
    error InterestPerSecondTooLow();
    error DeadlineAlreadyPassed();
    error CastOverflow();

    /* FUNCTIONS */

    function vault() external view returns (address);
    function storedInterestPerSecond() external view returns (uint96);
    function maxInterestPerSecond() external view returns (uint96);
    function deadline() external view returns (uint64);
    function setInterestPerSecondAndDeadline(uint256 newInterestPerSecond, uint256 newDeadline) external;
    function zeroInterestPerSecond() external;
    function setMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external;
    function zeroMaxInterestPerSecond() external;
}
