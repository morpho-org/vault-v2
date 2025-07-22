// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IVic} from "../../interfaces/IVic.sol";

interface IOnchainVic is IVic {
    /* ERRORS */

    error Unauthorized();

    /* FUNCTIONS */

    function parentVault() external view returns (address);
    function asset() external view returns (address);
}
