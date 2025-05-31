// SPDX-License-Identifier: GPL-2.0-or-later

import "Invariants.spec";

definition MAX_RATE_PER_SECOND() returns uint256 = (10^18 + 200 * 10^16) / (365 * 24 * 60 * 60);
definition WAD() returns uint256 = 10^18;

// Allows notably to check that nothing can go wrong with the VIC.
rule livenessAccrueInterestNoEntryGate(env e) {
    require e.msg.value == 0;
    
    // Safe require because timestamps are guaranteed to be increasing.
    require e.block.timestamp >= lastUpdate();
    // We assume that less than 10 years have passed since the last update.
    require e.block.timestamp - lastUpdate() <= 315360000;
    // Safe require as it corresponds to some time very far into the future.
    require e.block.timestamp < 2^64;

    require totalAssets() * MAX_RATE_PER_SECOND() < 2^256;
    require totalAssets() + (totalAssets() * MAX_RATE_PER_SECOND() / WAD()) * 315360000 < 2^192;
    require totalAssets() * (totalSupply() + 1) <= 2^256;
    require (totalAssets() + (totalAssets() * MAX_RATE_PER_SECOND() / WAD()) * 315360000) * 315360000 * (totalSupply() + 1) < 2^256;
    require totalSupply() < 2^256 - 1;
    
    // Safe require because we have the totalSupply invariant.
    require balanceOf(managementFeeRecipient()) <= totalSupply();
    require balanceOf(performanceFeeRecipient()) <= totalSupply();

    require enterGate() == 0;
    
    requireInvariant performanceFee();
    requireInvariant managementFee();
    requireInvariant performanceFeeRecipient();
    requireInvariant managementFeeRecipient();
    
    accrueInterest@withrevert(e);
    assert !lastReverted;
}

rule livenessAccrueInterestRecipientsAreAllowed(env e) {
    require e.msg.value == 0;
    
    // Safe require because timestamps are guaranteed to be increasing.
    require e.block.timestamp >= lastUpdate();
    // We assume that less than 10 years have passed since the last update.
    require e.block.timestamp - lastUpdate() <= 315360000;
    // Safe require as it corresponds to some time very far into the future.
    require e.block.timestamp < 2^64;

    require totalAssets() * MAX_RATE_PER_SECOND() < 2^256;
    require totalAssets() + (totalAssets() * MAX_RATE_PER_SECOND() / WAD()) * 315360000 < 2^192;
    require totalAssets() * (totalSupply() + 1) <= 2^256;
    require (totalAssets() + (totalAssets() * MAX_RATE_PER_SECOND() / WAD()) * 315360000) * 315360000 * (totalSupply() + 1) < 2^256;
    require totalSupply() < 2^256 - 1;
    
    // Safe require because we have the totalSupply invariant.
    require balanceOf(managementFeeRecipient()) <= totalSupply();
    require balanceOf(performanceFeeRecipient()) <= totalSupply();

    require canReceive(managementFeeRecipient());
    require canReceive(performanceFeeRecipient());
    
    requireInvariant performanceFee();
    requireInvariant managementFee();
    requireInvariant performanceFeeRecipient();
    requireInvariant managementFeeRecipient();
    
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

