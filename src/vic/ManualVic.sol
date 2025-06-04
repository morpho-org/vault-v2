// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IManualVic} from "./interfaces/IManualVic.sol";
import {MathLib} from "../libraries/MathLib.sol";

contract ManualVic is IManualVic {
    using MathLib for uint256;

    /* IMMUTABLES */

    address public immutable vault;

    /* STORAGE */

    uint256 public maxInterestPerSecond;
    uint128 internal _interestPerSecond;
    uint128 internal _deadline;

    /* GETTERS */

    function deadline() external view returns (uint256) {
        return uint256(_deadline);
    }

    /* FUNCTIONS */

    constructor(address _vault) {
        vault = _vault;
    }

    function increaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) public {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        require(newMaxInterestPerSecond >= maxInterestPerSecond, NotIncreasing());
        maxInterestPerSecond = newMaxInterestPerSecond;
        emit IncreaseMaxInterestPerSecond(maxInterestPerSecond);
    }

    function decreaseMaxInterestPerSecond(uint256 newMaxInterestPerSecond) public {
        require(msg.sender == IVaultV2(vault).curator() || IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        require(newMaxInterestPerSecond <= maxInterestPerSecond, NotDecreasing());
        require(_interestPerSecond <= newMaxInterestPerSecond, InterestPerSecondTooHigh());

        maxInterestPerSecond = newMaxInterestPerSecond;
        emit DecreaseMaxInterestPerSecond(msg.sender, maxInterestPerSecond);
    }

    function setInterestPerSecond(uint256 newInterestPerSecond, uint256 newDeadline) public {
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        require(newInterestPerSecond <= maxInterestPerSecond, InterestPerSecondTooHigh());
        require(newDeadline >= block.timestamp, DeadlineAlreadyPassed());

        IVaultV2(vault).accrueInterest();

        _interestPerSecond = newInterestPerSecond.toUint128();
        _deadline = uint128(newDeadline);
        emit SetInterestPerSecond(msg.sender, newInterestPerSecond, newDeadline);
    }

    function zeroInterestPerSecond() public {
        require(IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        _interestPerSecond = 0;
        _deadline = 0;
        emit ZeroInterestPerSecond(msg.sender);
    }

    /// @dev Returns the interest per second.
    function interestPerSecond(uint256, uint256) external view returns (uint256) {
        return block.timestamp <= _deadline ? _interestPerSecond : 0;
    }
}
