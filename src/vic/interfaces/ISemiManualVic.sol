// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IVic} from "../../interfaces/IVic.sol";

interface ISemiManualVic is IVic {
    /* EVENTS */

    event SetMaxInterestPerSecond(uint256 newMaxInterestPerSecond);
    event ZeroMaxInterestPerSecond(address indexed caller);

    /* ERRORS */

    error CastOverflow();
    error Unauthorized();

    /* FUNCTIONS */

    function vault() external view returns (address);
    function maxInterestPerSecond() external view returns (uint96);
    function setMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external;
    function zeroMaxInterestPerSecond() external;
}
