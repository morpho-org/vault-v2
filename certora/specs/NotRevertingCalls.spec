// SPDX-License-Identifier: GPL-2.0-or-later
using VicHelper as vicHelper;

methods {
    function vicHelper.setShouldRevert(bool) external envfree;
    function vicHelper.setIsReturnDataEmpty(bool) external envfree;
}


rule accrueInterestViewDoesntRevertOnBadVic(env e) {
    // Safe require because `accrueInterestView` is always called without native tokens.
    require e.msg.value == 0;

    bool shouldRevert;
    bool isReturnDataEmpty;

    vicHelper.setShouldRevert(shouldRevert);
    vicHelper.setIsReturnDataEmpty(isReturnDataEmpty);

    accrueInterestViewMocked@withrevert(e);
    if (shouldRevert && isReturnDataEmpty) {
        assert lastReverted;
    } else {
        assert !lastReverted;
    }
}
