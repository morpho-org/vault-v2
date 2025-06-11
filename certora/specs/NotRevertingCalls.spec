// SPDX-License-Identifier: GPL-2.0-or-later

rule accrueInterestViewDoesntRevertOnBadVic(env e) {
    // Safe require because `accrueInterestView` is always called without native tokens.
    require e.msg.value == 0;
    accrueInterestViewMocked@withrevert(e);
    assert !lastReverted;
}
