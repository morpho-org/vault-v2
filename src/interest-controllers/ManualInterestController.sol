// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IInterestController} from "../interfaces/IInterestController.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";

contract ManualInterestController is IInterestController {
    /* IMMUTABLES */

    address public immutable vault;

    /* STORAGE */

    uint256 internal _interestPerSecond;
    uint256 public maxInterestPerSecond;

    /* EVENTS */

    event SetInterestPerSecond(address indexed caller, uint256 newInterestPerSecond);
    event SetMaxInterestPerSecond(uint256 newMaxInterestPerSecond);

    /* ERRORS */

    error Unauthorized();
    error InterestPerSecondTooHigh();

    /* FUNCTIONS */

    constructor(address _vault) {
        vault = _vault;
    }

    function setMaxInterestPerSecond(uint256 newMaxInterestPerSecond) public {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        maxInterestPerSecond = newMaxInterestPerSecond;
        emit SetMaxInterestPerSecond(newMaxInterestPerSecond);
    }

    function setInterestPerSecond(uint256 newInterestPerSecond) public {
        require(IVaultV2(vault).isAllocator(msg.sender) || IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        require(newInterestPerSecond <= maxInterestPerSecond, InterestPerSecondTooHigh());
        _interestPerSecond = newInterestPerSecond;
        emit SetInterestPerSecond(msg.sender, newInterestPerSecond);
    }

    function interestPerSecond(uint256, uint256) external view returns (uint256) {
        return _interestPerSecond;
    }
}
