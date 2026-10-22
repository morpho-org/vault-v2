// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../../lib/midnight/src/interfaces/IGate.sol";

/// @dev Permission checks shared by every market using the enter gates of this subgate.
interface IEnterSubGate is IEnterGate {
    function roleSetter(bool creditSide) external view returns (address);
}
