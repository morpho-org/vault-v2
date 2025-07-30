// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import "../libraries/ConstantsLib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IOnchainVic} from "./interfaces/IOnchainVic.sol";

contract OnchainVic is IOnchainVic {
    using MathLib for uint256;

    /* EVENTS */
    event SetMaxRatePerSecond(uint256 maxRatePerSecond);

    /* ERRORS */
    error MaxRatePerSecondLimitExceeded();

    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable asset;
    uint256 public maxRatePerSecondLimit;

    /* STATE VARIABLES */

    uint256 public maxRatePerSecond;

    /* FUNCTIONS */

    constructor(address _parentVault) {
        parentVault = _parentVault;
        asset = IVaultV2(parentVault).asset();
        maxRatePerSecondLimit = 200e16 / uint256(365 days); // 200% APR
        maxRatePerSecond = 200e16 / uint256(365 days); // 200% APR
    }

    /// @dev Returns the interest per second.
    function interest(uint256 totalAssets, uint256 elapsed) external view returns (uint256) {
        uint256 realAssets = IERC20(asset).balanceOf(parentVault);
        for (uint256 i = 0; i < IVaultV2(parentVault).adaptersLength(); i++) {
            realAssets += IAdapter(IVaultV2(parentVault).adapters(i)).totalAssets();
        }
        uint256 _interest = realAssets.zeroFloorSub(totalAssets);
        uint256 maxInterest = (totalAssets * elapsed).mulDivDown(maxRatePerSecond, WAD);
        if (_interest > maxInterest) _interest = maxInterest;
        return _interest;
    }

    function setMaxRatePerSecond(uint256 _maxRatePerSecond) external {
        require(msg.sender == IVaultV2(parentVault).curator());
        require(_maxRatePerSecond <= maxRatePerSecondLimit, MaxRatePerSecondLimitExceeded());
        maxRatePerSecond = _maxRatePerSecond;
        emit SetMaxRatePerSecond(_maxRatePerSecond);
    }
}
