// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {ISemiManualVic} from "./interfaces/ISemiManualVic.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import "../libraries/ConstantsLib.sol";

import {MathLib} from "../libraries/MathLib.sol";

contract SemiManualVic is ISemiManualVic {
    using MathLib for uint256;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable vault;

    /* STORAGE */

    uint256 public targetTotalAssets;
    uint96 public maxInterestPerSecond;

    /* FUNCTIONS */

    constructor(address _vault) {
        vault = _vault;
        asset = IERC4626(_vault).asset();
    }

    function setMaxInterestPerSecond(uint256 newMaxInterestPerSecond) external {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        require(newMaxInterestPerSecond <= type(uint96).max, CastOverflow());
        maxInterestPerSecond = uint96(newMaxInterestPerSecond);
        emit SetMaxInterestPerSecond(maxInterestPerSecond);
    }

    function zeroMaxInterestPerSecond() external {
        require(IVaultV2(vault).isSentinel(msg.sender), Unauthorized());
        maxInterestPerSecond = 0;
        emit ZeroMaxInterestPerSecond(msg.sender);
    }

    /// @dev Requires to give the allocator role to this contract.
    function setTargetTotalAssets(address[] memory adapters, bytes[] memory data) external {
        require(adapters.length == data.length);
        uint256 realAssets = IERC20(asset).balanceOf(vault);
        for (uint256 i; i < adapters.length; i++) {
            bytes32[] memory ids = IVaultV2(vault).deallocate(adapters[i], data[i], 0);
            bytes32 id = ids[ids.length - 1];
            realAssets += IVaultV2(vault).allocation(id);
        }
        targetTotalAssets = realAssets;
    }

    function interest(uint256 totalAssets, uint256 elapsed) external view returns (uint256) {
        uint256 maxRate = maxInterestPerSecond > MAX_RATE_PER_SECOND ? MAX_RATE_PER_SECOND : maxInterestPerSecond;
        uint256 maxInterest = (totalAssets * elapsed).mulDivDown(maxRate, WAD);
        uint256 tentativeInterest = targetTotalAssets.zeroFloorSub(totalAssets);
        return tentativeInterest <= maxInterest ? tentativeInterest : maxInterest;
    }
}
