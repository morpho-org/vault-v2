// SPDX-License-Identifier: GPL-2.0-or-later

import "Invariants.spec";

methods {
    // function _.canReceiveShares(address account) external => CONSTANT;
}

// Check that setVic cannot revert.
// Disclaimer: this does not check reasons related to gas usage.
rule setVicCannotRevertIfDataIsTimelocked(env e, address newVic) {
    // Safe require because `setVic` is always called without native tokens.
    require e.msg.value == 0;

    setVicMocked@withrevert(e, newVic);
    assert !lastReverted;
}
