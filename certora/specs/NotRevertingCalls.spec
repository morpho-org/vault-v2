// SPDX-License-Identifier: GPL-2.0-or-later

// Check that setVic cannot revert.
// Disclaimer: this does not check reasons related to gas.
rule setVicCannotRevertIfDataIsTimelocked(env e, address newVic) {
    // Safe require because `setVic` is always called without native tokens.
    require e.msg.value == 0;

    setVicMocked@withrevert(e, newVic);
    assert !lastReverted;
}
