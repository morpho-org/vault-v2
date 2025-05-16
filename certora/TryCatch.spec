// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function liquidityData() external returns(bytes) envfree;
}

rule liquidityAdapterDoesntRevertWhenDepositing(env e, uint256 assets, uint256 shares, address onBehalf) {
    require e.msg.value == 0;
    require liquidityData().length == 0;
    enterExternal@withrevert(e, assets, shares, onBehalf);
    assert !lastReverted;
}
