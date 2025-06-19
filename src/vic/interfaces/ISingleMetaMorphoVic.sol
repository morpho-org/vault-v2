// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IVic} from "../../interfaces/IVic.sol";

interface ISingleMetaMorphoVic is IVic {
    /* FUNCTIONS */

    function metaMorphoAdapter() external view returns (address);
}
