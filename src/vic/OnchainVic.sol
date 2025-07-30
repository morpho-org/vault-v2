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

    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable asset;

    /* FUNCTIONS */

    constructor(address _parentVault) {
        parentVault = _parentVault;
        asset = IVaultV2(parentVault).asset();
    }

    /// @dev Returns the interest per second.
    function interest(uint256 totalAssets, uint256) external view returns (uint256) {
        uint256 realAssets = IERC20(asset).balanceOf(parentVault);
        for (uint256 i = 0; i < IVaultV2(parentVault).adaptersLength(); i++) {
            realAssets += IAdapter(IVaultV2(parentVault).adapters(i)).totalAssets();
        }
        return realAssets.zeroFloorSub(totalAssets);
    }
}
