// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function liquidityData() external returns(bytes) envfree;
}

rule liquidityAdapterDoesntRevertWhenDepositing(env e, uint256 assets, uint256 shares, address onBehalf) {
    // Safe require because `enter` is always called without native tokens.
    require e.msg.value == 0;
    // Safe no-op require, that prevents a weird behavior where the state could be havoced such that liquidityData would not represent bytes.
    require liquidityData().length >= 0;
    enterMocked@withrevert(e, assets, shares, onBehalf);
    assert !lastReverted;
}

rule accrueInterestViewDoesntRevertOnBadVic(env e) {
    // Safe require because `accrueInterestView` is always called without native tokens.
    require e.msg.value == 0;
    accrueInterestViewMocked@withrevert(e);
    assert !lastReverted;
}
