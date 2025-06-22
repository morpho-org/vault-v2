// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function isMorphoVaultV1Adapter(address) external returns bool envfree;

    function Utils.factory(address) external returns address envfree;
    function _.factory() external => DISPATCHER(true);
}

strong invariant genuineAdaptersReturnTheFactory(address adapter)
    isMorphoVaultV1Adapter(adapter) => Utils.factory(adapter) == currentContract;
