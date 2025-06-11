// SPDX-License-Identifier: GPL-2.0-or-later

import "Invariants.spec";

using VicHelper as vicHelper;

methods {
    function vicHelper.setShouldRevert(bool) external envfree;
    function vicHelper.setReturnDataLength(uint) external envfree;
    function _.canReceiveShares(address account) external => CONSTANT;
}

definition TEN_YEARS() returns uint256 = assert_uint256(365 * 24 * 60 * 60 * 10);

// Only checks varying return data length, not varying return data content.
rule accrueInterestViewOnlyRevertsOnEmptyRevert(env e) {
    // Safe require because `accrueInterestView` is always called without native tokens.
    require e.msg.value == 0;

    bool shouldRevert;
    uint returnDataLength;

    uint _lastUpdate = lastUpdate();
     // Safe require because timestamps are guaranteed to be increasing.
    require e.block.timestamp >= _lastUpdate;
    // We assume that less than 10 years have passed since the last update.
    require e.block.timestamp - _lastUpdate <= TEN_YEARS();
    // Safe require as it corresponds to some time very far into the future.
    require e.block.timestamp < 2^64;
    // Safe requires because they are very large numbers.
    require totalAssets(e) < 2^112; // 10 years of max interest multiplies assets by approximately 2^16.
    require totalSupply() < 2^128;
    // Safe requires because of the totalSupplyIsSumOfBalances invariant.
    require balanceOf(managementFeeRecipient()) <= totalSupply();
    require balanceOf(performanceFeeRecipient()) <= totalSupply();
    requireInvariant performanceFee();
    requireInvariant managementFee();
    requireInvariant performanceFeeRecipient();
    requireInvariant managementFeeRecipient();

    // Necessary condition for the rule to be true.
    require enterGate() == 0 || (canReceive(performanceFeeRecipient()) && canReceive(managementFeeRecipient()));

    vicHelper.setShouldRevert(shouldRevert);
    vicHelper.setReturnDataLength(returnDataLength);

    accrueInterestView@withrevert(e);
    if (e.block.timestamp > _lastUpdate && shouldRevert && returnDataLength == 0) {
        assert lastReverted;
    } else {
        assert !lastReverted;
    }
}
