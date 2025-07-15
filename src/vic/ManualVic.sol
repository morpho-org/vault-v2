// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IManualVic} from "./interfaces/IManualVic.sol";

contract ManualVic is IManualVic {
    /* IMMUTABLES */

    address public immutable vault;

    /* STORAGE */

    uint96 public maxInterestPerSecond;
    uint96 public storedInterestPerSecond;
    uint64 public deadline;

    /* FUNCTIONS */

    constructor(address _vault) {
        vault = _vault;
    }

    function setMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        require(newMaxInterestPerSecond >= storedInterestPerSecond, InterestPerSecondTooHigh());
        require(newMaxInterestPerSecond <= type(uint96).max, CastOverflow());
        maxInterestPerSecond = uint96(newMaxInterestPerSecond);
        emit SetMaxInterestPerSecond(maxInterestPerSecond);
    }

    function zeroMaxInterestPerSecond() external {
        require(IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        require(storedInterestPerSecond == 0, InterestPerSecondTooHigh());
        maxInterestPerSecond = 0;
        emit ZeroMaxInterestPerSecond(msg.sender);
    }

    function setInterestPerSecondAndDeadline(uint256 newInterestPerSecond, uint256 newDeadline) external {
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        require(newInterestPerSecond <= maxInterestPerSecond, InterestPerSecondTooHigh());
        require(newDeadline >= block.timestamp, DeadlineAlreadyPassed());
        require(newDeadline <= type(uint64).max, CastOverflow());

        IVaultV2(vault).accrueInterest();

        // Safe cast because newInterestPerSecond <= maxInterestPerSecond.
        storedInterestPerSecond = uint96(newInterestPerSecond);
        deadline = uint64(newDeadline);
        emit SetInterestPerSecondAndDeadline(msg.sender, newInterestPerSecond, newDeadline);
    }

    function zeroInterestPerSecondAndDeadline() external {
        require(IVaultV2(vault).isSentinel(msg.sender), Unauthorized());

        IVaultV2(vault).accrueInterest();

        storedInterestPerSecond = 0;
        deadline = 0;
        emit ZeroInterestPerSecondAndDeadline(msg.sender);
    }

    /// @dev Returns the interest per second.
    function interestPerSecond(uint256, uint256) external view returns (uint256) {
        return block.timestamp <= deadline ? storedInterestPerSecond : 0;
    }
}
