// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IManualVic} from "./interfaces/IManualVic.sol";

contract ManualVic is IManualVic {
    /* IMMUTABLES */

    address public immutable vault;

    /* STORAGE */

    uint96 public maxInterestPerSecond;
    uint96 public _interestPerSecond;
    uint64 public deadline;

    /* FUNCTIONS */

    constructor(address _vault) {
        vault = _vault;
    }

    function increaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) public {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        require(newMaxInterestPerSecond >= maxInterestPerSecond, NotIncreasing());
        require(newMaxInterestPerSecond <= type(uint96).max, CastOverflow());
        maxInterestPerSecond = uint96(newMaxInterestPerSecond);
        emit IncreaseMaxInterestPerSecond(maxInterestPerSecond);
    }

    function decreaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) public {
        require(msg.sender == IVaultV2(vault).curator() || IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        require(newMaxInterestPerSecond <= maxInterestPerSecond, NotDecreasing());
        require(_interestPerSecond <= newMaxInterestPerSecond, InterestPerSecondTooHigh());
        maxInterestPerSecond = uint96(newMaxInterestPerSecond);
        emit DecreaseMaxInterestPerSecond(msg.sender, maxInterestPerSecond);
    }

    function increaseInterestPerSecond(uint256 newInterestPerSecond, uint256 newDeadline) public {
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        require(newInterestPerSecond <= maxInterestPerSecond, InterestPerSecondTooHigh());
        require(newInterestPerSecond >= _interestPerSecond, NotIncreasing());
        require(newDeadline >= block.timestamp, DeadlineReached());
        require(newDeadline <= type(uint64).max, CastOverflow());

        IVaultV2(vault).accrueInterest();

        _interestPerSecond = uint96(newInterestPerSecond);
        deadline = uint64(newDeadline);
        emit IncreaseInterestPerSecond(msg.sender, newInterestPerSecond);
    }

    function decreaseInterestPerSecond(uint256 newInterestPerSecond, uint256 newDeadline) public {
        require(IVaultV2(vault).isAllocator(msg.sender) || IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        require(newInterestPerSecond <= _interestPerSecond, NotDecreasing());
        require(newDeadline >= block.timestamp, DeadlineReached());
        require(newDeadline <= type(uint64).max, CastOverflow());

        IVaultV2(vault).accrueInterest();

        _interestPerSecond = uint96(newInterestPerSecond);
        deadline = uint64(newDeadline);
        emit DecreaseInterestPerSecond(msg.sender, newInterestPerSecond);
    }

    /// @dev Returns the interest per second.
    function interestPerSecond(uint256, uint256) external view returns (uint256) {
        return block.timestamp <= deadline ? _interestPerSecond : 0;
    }
}
