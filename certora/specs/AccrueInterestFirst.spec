// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function accrueInterest() internal => accrueInterestSummary();
}

ghost bool accrued;

ghost bool storageAccessedBeforeAccrual;

function accrueInterestSummary() {
    accrued = true;
}

hook ALL_SLOAD(uint _) uint _ {
    if (!accrued) {
        storageAccessedBeforeAccrual = true;
    }
}

hook ALL_SSTORE(uint _, uint _) {
    if (!accrued) {
        storageAccessedBeforeAccrual = true;
    }
}

hook ALL_TLOAD(uint _) uint _ {
    if (!accrued) {
        storageAccessedBeforeAccrual = true;
    }
}

hook ALL_TSTORE(uint _, uint _) {
    if (!accrued) {
        storageAccessedBeforeAccrual = true;
    }
}

// Check that functions accruing interest do it before any storage read or write.
rule noStorageAccessBeforeAccrueInterest(method f, env e, calldataarg data)
filtered {
    // Functions checking roles or timelocks before accruing interest.
    f -> f.selector != sig:setPerformanceFee(uint256).selector
        && f.selector != sig:setManagementFee(uint256).selector
        && f.selector != sig:setPerformanceFeeRecipient(address).selector
        && f.selector != sig:setManagementFeeRecipient(address).selector
        && f.selector != sig:allocate(address, bytes, uint256).selector
        && f.selector != sig:setMaxRate(uint256).selector
        &&
        // forceDeallocate deallocates before withdrawing.
        f.selector != sig:forceDeallocate(address, bytes, uint256, address).selector
} {
    require !accrued, "setup ghost state";
    require !storageAccessedBeforeAccrual, "setup ghost state";

    f(e, data);

    assert accrued => !storageAccessedBeforeAccrual;
}
