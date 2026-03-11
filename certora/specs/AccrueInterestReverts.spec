// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using Utils as Utils;

methods {
    function Utils.maxMaxRate() external returns (uint256) envfree;
    function Utils.maxPerformanceFee() external returns (uint256) envfree;
    function Utils.maxManagementFee() external returns (uint256) envfree;
    function lastUpdate() external returns (uint64) envfree;
    function totalSupply() external returns (uint256) envfree;
    function virtualShares() external returns (uint256) envfree;
    function managementFee() external returns (uint96) envfree;
    function balanceOf(address account) external returns (uint256) envfree;

    // `balanceOf` is assumed to not revert and summarized to a bounded value.
    function _.balanceOf(address account) external => summaryBalanceOf() expect(uint256) ALL;

    // `realAssets` is assumed to not revert and summarized to a bounded value.
    function _.realAssets() external => summaryRealAssets() expect(uint256);

    // Trick to be able to retrieve the value returned by the corresponding contract before it is called,
    // without the value changing between the retrieval and the call.
    function _.canReceiveShares(address account) external => ghostCanReceiveShares(calledContract, account) expect(bool);
}

ghost ghostCanReceiveShares(address, address) returns bool;

// Returns a value bounded by 10 ^ 35.
function summaryBalanceOf() returns uint256 {
    uint256 balance;
    require balance < 10 ^ 35, "vault balance is less than totalAssets and totalAssets is assumed to be bounded by 10 ^ 35";
    return balance;
}

// Returns a value bounded by 10 ^ 35.
function summaryRealAssets() returns uint256 {
    uint256 realAssets;
    require realAssets < 10 ^ 35, "realAssets from each adapter is less than totalAssets and totalAssets is assumed to be bounded by 10 ^ 35";
    return realAssets;
}

// This rule captures the conditions under which accrueInterestView does not revert.
// Assumes balanceOf, realAssets and canReceiveShares do not revert and return values bounded by 10 ^ 35.
// Shows that the returned values are bounded.
// Further, shows that performanceFee == 0 => performanceFeeShares == 0 and managementFee == 0 => managementFeeShares == 0
rule accrueInterestViewRevertCondition(env e) {

    // explicit assumptions required for the rule.
    require(currentContract._totalAssets < 10 ^ 35, "totalAssets is bounded by 10 ^ 35");
    require(totalSupply() < 10 ^ 35, "totalSupply is assumed to be less than 10 ^ 35");
    require(e.block.timestamp - currentContract.lastUpdate() < 10 * 365 * 24 * 60 * 60, "time elapsed is assumed to be < 10 years");

    // Call set-up and proven invariants
    require(e.msg.value == 0, "setup the call");
    require(e.block.timestamp >= currentContract.lastUpdate(), "block timestamps are guaranteed to be non-decreasing");
    require(virtualShares() <= 10 ^ 18, "see virtualSharesBound invariant in Invariants.spec; virtualShares is bounded by 10 ^ 18");
    require(performanceFee() <= Utils.maxPerformanceFee(), "see PerformanceFeeBound invariant in Invariants.spec; bounded by 0.5 * 10 ^ 18");
    require(managementFee() <= Utils.maxManagementFee(), "see ManagementFeeBound invariant in Invariants.spec;  bounded by 0.05 * 10 ^ 18 / 365 days");
    require(maxRate() <= Utils.maxMaxRate(), "see maxRateBound invariant in Invariants.spec; maxRate is bounded by 2 * 10 ^ 18 / 365 days");

    uint256 newTotalAssets;
    uint256 performanceFeeShares;
    uint256 managementFeeShares;
    newTotalAssets, performanceFeeShares, managementFeeShares = accrueInterestView@withrevert(e);

    assert !lastReverted;

    // Guarantees on returned values of accrueInterestView.
    assert newTotalAssets < 2 ^ 128;
    assert performanceFeeShares < 2 ^ 236;
    assert managementFeeShares < 2 ^ 236;
    assert performanceFee() != 0 || performanceFeeShares == 0;
    assert managementFee() != 0 || managementFeeShares == 0;
}

// This rule captures the conditions under which accrueInterest does not revert.
// Assumes balanceOf and realAssets do not revert and return values bounded by 10 ^ 35.
rule accrueInterestRevertCondition(env e) {

    // explicit assumptions required for the rule.
    require(currentContract._totalAssets < 10 ^ 35, "totalAssets is bounded by 10 ^ 35");
    require(totalSupply() < 10 ^ 35, "totalSupply is assumed to be less than 10 ^ 35");
    require(e.block.timestamp - currentContract.lastUpdate() < 10 * 365 * 24 * 60 * 60, "current block timestamp should be < 10 years from lastUpdate");
    require(balanceOf(performanceFeeRecipient()) < 2 ^ 256 - 2 ^ 236, "balance of performance fee recipient should be less than 2 ^ 256 - max performanceFeeShare; see accrueInterestViewRevertCondition");
    require(balanceOf(managementFeeRecipient()) < 2 ^ 256 - 2 ^ 236, "balance of management fee recipient should be less than 2 ^ 256 - max managementFeeShare; see accrueInterestViewRevertCondition");

    // Call set-up and proven invariants
    require(e.msg.value == 0, "setup the call");
    require(performanceFeeRecipient() != 0, "set up the call");
    require(managementFeeRecipient() != 0, "setup the call");
    require(e.block.timestamp >= currentContract.lastUpdate(), "block timestamps are guaranteed to be non-decreasing");
    require(virtualShares() <= 10 ^ 18, "see virtualSharesBound invariant in Invariants.spec; virtualShares is bounded by 10 ^ 18");
    require(performanceFee() <= Utils.maxPerformanceFee(), "see PerformanceFeeBound invariant in Invariants.spec; bounded by 0.5 * 10 ^ 18");
    require(managementFee() <= Utils.maxManagementFee(), "see ManagementFeeBound invariant in Invariants.spec;  bounded by 0.05 * 10 ^ 18 / 365 days");
    require(maxRate() <= Utils.maxMaxRate(), "see maxRateBound invariant in Invariants.spec; maxRate is bounded by 2 * 10 ^ 18 / 365 days");

    accrueInterest@withrevert(e);

    assert !lastReverted;
}
