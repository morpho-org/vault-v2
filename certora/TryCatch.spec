// SPDX-License-Identifier: GPL-2.0-or-later

rule liquidityAdapterDoesntRevertWhenDepositing(env e, uint256 assets, uint256 shares, address onBehalf) {
    enterExternal@withrevert(e, assets, shares, onBehalf);
    assert !lastReverted;
}
