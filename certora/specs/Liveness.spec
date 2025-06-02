// SPDX-License-Identifier: GPL-2.0-or-later

import "Invariants.spec";

methods {
    function _.canReceiveShares(address account) external => CONSTANT;
}

definition MAX_RATE_PER_SECOND() returns uint256 = (10^18 + 200 * 10^16) / (365 * 24 * 60 * 60);
definition WAD() returns uint256 = 10^18;
definition TEN_YEARS() returns uint256 = 315360000;

// Check that the VIC can't revert.
// Note: the property also requires gas assumptions; these are checked with testing (probably mention the file/test suite of interest).
rule livenessAccrueInterest(env e) {
    require e.msg.value == 0;
    
    // Safe require because timestamps are guaranteed to be increasing.
    require e.block.timestamp >= lastUpdate();
    // We assume that less than 10 years have passed since the last update.
    require e.block.timestamp - lastUpdate() <= TEN_YEARS();
    // Safe require as it corresponds to some time very far into the future.
    require e.block.timestamp < 2^64;
    // Safe requires because they are very large numbers.
    require totalAssets() < 2^112; // 10 years of max interest multiplies assets by approximately 2^16.
    require totalSupply() < 2^128;
    // Safe requires because of the totalSupply invariant.
    require balanceOf(managementFeeRecipient()) <= totalSupply();
    require balanceOf(performanceFeeRecipient()) <= totalSupply();
    requireInvariant performanceFee();
    requireInvariant managementFee();
    requireInvariant performanceFeeRecipient();
    requireInvariant managementFeeRecipient();

    // Necessary condition for the rule to be true.
    require enterGate() == 0 || (canReceive(performanceFeeRecipient()) && canReceive(managementFeeRecipient()));
    
    accrueInterest@withrevert(e);
    assert !lastReverted;
}

rule livenessDecreaseAbsoluteCapZero(env e, bytes idData) {
    require e.msg.sender == curator() || isSentinel(e.msg.sender);
    require e.msg.value == 0;
    decreaseAbsoluteCap@withrevert(e, idData, 0);
    assert !lastReverted;
}

rule livenessDecreaseRelativeCapZero(env e, bytes idData) {
    require e.msg.sender == curator() || isSentinel(e.msg.sender);
    require e.msg.value == 0;
    decreaseRelativeCap@withrevert(e, idData, 0);
    assert !lastReverted;
}

rule livenessSetOwner(env e, address owner) {
    require e.msg.sender == owner();
    require e.msg.value == 0;
    setOwner@withrevert(e, owner);
    assert !lastReverted;
}

rule livenessSetCurator(env e, address curator) {
    require e.msg.sender == owner();
    require e.msg.value == 0;
    setCurator@withrevert(e, curator);
    assert !lastReverted;
}

rule livenessSetIsSentinel(env e, address account, bool isSentinel) {
    require e.msg.sender == owner();
    require e.msg.value == 0;
    setIsSentinel@withrevert(e, account, isSentinel);
    assert !lastReverted;
}

