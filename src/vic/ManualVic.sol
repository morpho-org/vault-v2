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

    function setMaxInterestPerSecond(uint256 newMaxInterestPerSecond) public {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        require(newMaxInterestPerSecond >= _interestPerSecond, InterestPerSecondTooHigh());
        require(newMaxInterestPerSecond <= type(uint96).max, CastOverflow());
        maxInterestPerSecond = uint96(newMaxInterestPerSecond);
        emit SetMaxInterestPerSecond(maxInterestPerSecond);
    }

    function zeroMaxInterestPerSecond() public {
        require(IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        require(_interestPerSecond == 0, InterestPerSecondTooHigh());
        maxInterestPerSecond = 0;
        emit ZeroMaxInterestPerSecond(msg.sender);
    }

    function setInterestPerSecond(uint256 newInterestPerSecond, uint256 newDeadline) public {
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        require(newInterestPerSecond <= maxInterestPerSecond, InterestPerSecondTooHigh());
        require(newDeadline >= block.timestamp, DeadlineAlreadyPassed());
        require(newInterestPerSecond <= type(uint96).max, CastOverflow());
        require(newDeadline <= type(uint64).max, CastOverflow());

        IVaultV2(vault).accrueInterest();

        _interestPerSecond = uint96(newInterestPerSecond);
        deadline = uint64(newDeadline);
        emit SetInterestPerSecond(msg.sender, newInterestPerSecond, newDeadline);
    }

    function zeroInterestPerSecond() public {
        require(IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        _interestPerSecond = 0;
        deadline = 0;
        emit ZeroInterestPerSecond(msg.sender);
    }

    /// @dev Returns the interest per second.
    function interestPerSecond(uint256, uint256) external view returns (uint256) {
        return block.timestamp <= deadline ? _interestPerSecond : 0;
    }
}
