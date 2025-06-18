// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";

contract VaultV2Harness is VaultV2 {
    constructor(address lens, address owner, address asset) VaultV2(lens, owner, asset) {}

    function setVicMocked(address newVic) external {
        try this.accrueInterest() {}
        catch {
            lastUpdate = uint64(block.timestamp);
        }
        vic = newVic;
        emit EventsLib.SetVic(newVic);
    }
}
