// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVic} from "../interfaces/IVic.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";

contract ManualVic is IVic {
    /* IMMUTABLES */

    address public immutable vault;

    /* STORAGE */

    uint256 internal _interestPerSecond;
    uint256 public maxInterestPerSecond;

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

    function interestPerSecond(uint256, uint256) external view returns (uint256) {
        return _interestPerSecond;
    }
}
