// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IExponentialDecayVic} from "./interfaces/IExponentialDecayVic.sol";
import "../libraries/MathLib.sol";

contract ExponentialDecayVic is IExponentialDecayVic {
    using MathLib for uint256;

    /* CONSTANTS */

    uint256 constant LN2 = 0.693147180559945309e18; // in WAD

    /* IMMUTABLES */

    address public immutable vault;

    /* STORAGE */

    uint256 internal targetInterestPerSecond;
    uint256 public maxInterestPerSecond;
    uint256 public currentRate;
    // ln2/half-life
    uint256 decayRate = LN2 / (0.25 hours);

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
        require(targetInterestPerSecond <= newMaxInterestPerSecond, TargetInterestPerSecondTooHigh());

        maxInterestPerSecond = newMaxInterestPerSecond;
        emit DecreaseMaxInterestPerSecond(msg.sender, maxInterestPerSecond);
    }

    function setTargetInterestPerSecond(uint256 newTargetInterestPerSecond) public {
        require(IVaultV2(vault).isAllocator(msg.sender) || IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        require(newTargetInterestPerSecond <= maxInterestPerSecond, TargetInterestPerSecondTooHigh());

        IVaultV2(vault).accrueInterest();

        targetInterestPerSecond = newTargetInterestPerSecond;
        emit SetTargetInterestPerSecond(msg.sender, newTargetInterestPerSecond);
    }

    /// initially 15 minutes
    function setDecayHalfLife(uint256 halfLifeInSeconds) public {
        require(msg.sender == IVaultV2(vault).curator() || IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        decayRate = LN2 / halfLifeInSeconds;
    }

    /// @dev Returns a rate that exponentially approaches the correct rate given the target interests per second.
    function updateCurrentRate(uint256 totalAssets, uint256 elapsed) internal view returns (uint256 newIPS) {
        uint256 targetRate = targetInterestPerSecond * WAD / totalAssets;

        // e^(−decayRate * elapsed) = 1 / (1 + e^(decayRate * elapsed) - 1)
        uint256 decay = WAD * WAD / (WAD + decayRate.wTaylorCompounded(elapsed));

        uint256 newRate;
        if (currentRate >= targetRate) {
            newRate = targetRate + (currentRate - targetRate) * decay / WAD;
        } else {
            newRate = targetRate - (targetRate - currentRate) * decay / WAD;
        }

        uint256 maxRate = maxInterestPerSecond * WAD / totalAssets;

        return MathLib.min(newRate, maxRate);
    }

    function interestPerSecondView(uint256 totalAssets, uint256 elapsed) external view returns (uint256) {
        return updateCurrentRate(totalAssets, elapsed) * totalAssets / WAD;
    }

    function interestPerSecond(uint256 totalAssets, uint256 elapsed) external returns (uint256) {
        require(msg.sender == vault, ErrorsLib.Unauthorized());
        currentRate = updateCurrentRate(totalAssets, elapsed);

        return currentRate * totalAssets / WAD;
    }
}
