// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IVic} from "../../interfaces/IVic.sol";

interface ISingleMorphoVaultV1Vic is IVic {
    function asset() external view returns (address);
    function morphoVaultV1Adapter() external view returns (address);
    function morphoVaultV1() external view returns (address);
    function parentVault() external view returns (address);
}
