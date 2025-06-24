// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {ISingleMorphoVaultV1Vic} from "./interfaces/ISingleMorphoVaultV1Vic.sol";
import {IMorphoVaultV1Adapter} from "../adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {MathLib} from "../libraries/MathLib.sol";

contract SingleMorphoVaultV1Vic is ISingleMorphoVaultV1Vic {
    using MathLib for uint256;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable morphoVaultV1Adapter;
    address public immutable morphoVaultV1;
    address public immutable parentVault;

    /* FUNCTIONS */

    constructor(address _parentVault, address _morphoVaultV1Adapter) {
        parentVault = _parentVault;
        morphoVaultV1Adapter = _morphoVaultV1Adapter;
        address _morphoVaultV1 = IMorphoVaultV1Adapter(_morphoVaultV1Adapter).morphoVaultV1();
        morphoVaultV1 = _morphoVaultV1;
        asset = IERC4626(_morphoVaultV1).asset();
    }

    /// @dev Returns the interest per second.
    function interestPerSecond(uint256 totalAssets, uint256 elapsed) external view returns (uint256) {
        uint256 realAssets = IERC4626(morphoVaultV1).previewRedeem(
            IERC4626(morphoVaultV1).balanceOf(morphoVaultV1Adapter)
        ) + IERC20(asset).balanceOf(parentVault);
        return (realAssets.zeroFloorSub(totalAssets) / elapsed);
    }
}
