// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {ISingleMorphoVaultV1Vic} from "./interfaces/ISingleMorphoVaultV1Vic.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IMorphoVaultV1Adapter} from "../adapters/interfaces/IMorphoVaultV1Adapter.sol";

import {MathLib} from "../libraries/MathLib.sol";

contract SingleMorphoVaultV1Vic is ISingleMorphoVaultV1Vic {
    using MathLib for uint256;

    /* IMMUTABLES */

    address public immutable morphoVaultV1Adapter;
    address public immutable morphoVaultV1;

    /* FUNCTIONS */

    constructor(address _morphoVaultV1Adapter) {
        morphoVaultV1Adapter = _morphoVaultV1Adapter;
        morphoVaultV1 = IMorphoVaultV1Adapter(_morphoVaultV1Adapter).morphoVaultV1();
    }

    /// @dev Returns the interest per second.
    function interestPerSecond(uint256 totalAssets, uint256 elapsed) external view returns (uint256) {
        return IERC4626(morphoVaultV1).previewRedeem(IERC4626(morphoVaultV1).balanceOf(morphoVaultV1Adapter))
            .zeroFloorSub(totalAssets) / elapsed;
    }
}
