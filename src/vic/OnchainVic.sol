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

    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable asset;

    /* STATE VARIABLES */

    uint256 public maxRatePerSecond;

    /* FUNCTIONS */

    constructor(address _parentVault) {
        parentVault = _parentVault;
        asset = IVaultV2(parentVault).asset();
        maxRatePerSecond = MAX_RATE_PER_SECOND;
    }

    /// @dev Returns the interest per second.
    function interest(uint256 totalAssets, uint256 elapsed) external view returns (uint256) {
        uint256 realAssets = IVaultV2(parentVault).realAssets();
        uint256 _interest = realAssets.zeroFloorSub(totalAssets);
        uint256 maxInterest = (totalAssets * elapsed).mulDivDown(maxRatePerSecond, WAD);
        return MathLib.min(_interest, maxInterest);
    }

    function setMaxRatePerSecond(uint256 _maxRatePerSecond) external {
        require(msg.sender == IVaultV2(parentVault).curator());
        maxRatePerSecond = _maxRatePerSecond;
        emit SetMaxRatePerSecond(_maxRatePerSecond);
    }
}
