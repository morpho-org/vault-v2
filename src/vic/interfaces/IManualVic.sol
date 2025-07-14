// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IVic} from "../../interfaces/IVic.sol";

interface IManualVic is IVic {
    /* EVENTS */

    event SetInterestPerSecondAndDeadline(address indexed caller, uint256 newInterestPerSecond, uint256 newDeadline);
    event SetMaxInterestPerSecond(uint256 newMaxInterestPerSecond);
    event ZeroInterestPerSecondAndDeadline(address indexed caller);
    event ZeroMaxInterestPerSecond(address indexed caller);

    /* ERRORS */

    error CastOverflow();
    error DeadlineAlreadyPassed();
    error InterestPerSecondTooHigh();
    error InterestPerSecondTooLow();
    error Unauthorized();

    /* FUNCTIONS */

    function vault() external view returns (address);
    function storedInterestPerSecond() external view returns (uint96);
    function maxInterestPerSecond() external view returns (uint96);
    function deadline() external view returns (uint64);
    function setInterestPerSecondAndDeadline(uint256 newInterestPerSecond, uint256 newDeadline) external;
    function zeroInterestPerSecondAndDeadline() external;
    function setMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external;
    function zeroMaxInterestPerSecond() external;
}
