// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IManualVic} from "./interfaces/IManualVic.sol";

contract ManualVic is IManualVic {
    /* IMMUTABLES */

    address public immutable vault;

    /* STORAGE */

    uint256 internal _interestPerSecond;
    uint256 public maxInterestPerSecond;

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

    function setInterestPerSecond(uint256 newInterestPerSecond) public {
        require(IVaultV2(vault).isAllocator(msg.sender) || IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        require(newInterestPerSecond <= maxInterestPerSecond, InterestPerSecondTooHigh());

        IVaultV2(vault).accrueInterest();

        _interestPerSecond = newInterestPerSecond;
        emit SetInterestPerSecond(msg.sender, newInterestPerSecond);
    }

    /// @dev Returns the interest per second.
    function interestPerSecond(uint256, uint256) external view returns (uint256) {
        return _interestPerSecond;
    }
}
