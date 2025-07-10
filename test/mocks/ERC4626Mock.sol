// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MathLib} from "../../src/libraries/MathLib.sol";

import {
    ERC4626,
    IERC20,
    IERC20Metadata,
    ERC20
} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

contract ERC4626Mock is ERC4626 {
    constructor(address asset_) ERC4626(IERC20(asset_)) ERC20("mock vault", "MOCK") {}

    function _decimalsOffset() internal view virtual override returns (uint8) {
        return uint8(MathLib.zeroFloorSub(18, IERC20Metadata(asset()).decimals()));
    }
}
