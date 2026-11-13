// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

/// @dev Permission checks shared by every market using the enter gates of this subgate.
interface IEnterSubGate {
    function roleSetter(bool creditSide) external view returns (address);
    function creditIncreaseAllowed(address account) external view returns (bool);
    function debtIncreaseAllowed(address account) external view returns (bool);
}
