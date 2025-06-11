// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";

contract VaultV2Harness is VaultV2 {
    constructor(address owner, address asset) VaultV2(owner, asset) {}

    // Remove timelocked modifier as this is not checked for revert reasons.in setVicCannotRevertIfDataIsTimelocked.
    function setVicMocked(address newVic) external {
        if (vic.code.length != 0) try this.accrueInterest() {} catch {}
        lastUpdate = uint64(block.timestamp);
        vic = newVic;
        emit EventsLib.SetVic(newVic);
    }
}
