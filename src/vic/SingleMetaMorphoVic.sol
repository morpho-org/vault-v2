// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {ISingleMetaMorphoVic} from "./interfaces/ISingleMetaMorphoVic.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IMetaMorphoAdapter} from "../adapters/interfaces/IMetaMorphoAdapter.sol";

import {MathLib} from "../libraries/MathLib.sol";

contract SingleMetaMorphoVic is ISingleMetaMorphoVic {
    using MathLib for uint256;

    /* IMMUTABLES */

    address public immutable metaMorphoAdapter;

    /* FUNCTIONS */

    constructor(address _metaMorphoAdapter) {
        metaMorphoAdapter = _metaMorphoAdapter;
    }

    /// @dev Returns the interest per second.
    function interestPerSecond(uint256 totalAssets, uint256 elapsed) external view returns (uint256) {
        address metaMorpho = IMetaMorphoAdapter(metaMorphoAdapter).metaMorpho();
        return IERC4626(metaMorpho).previewRedeem(IERC4626(metaMorpho).balanceOf(metaMorphoAdapter)).zeroFloorSub(
            totalAssets
        ) / elapsed;
    }
}
