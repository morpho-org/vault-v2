// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IRoleSetter {
    function roleSetter(bool creditSide) external view returns (address);
}
