// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using Utils as Utils;

// This specification checks either the revert condition or the input validation under which a function reverts.
// Interest accrual is assumed to not revert.

methods {
    function Utils.maxMaxRate() external returns (uint256) envfree;
    function Utils.maxPerformanceFee() external returns (uint256) envfree;
    function Utils.maxManagementFee() external returns (uint256) envfree;
    function lastUpdate() external returns (uint64) envfree;
    function totalSupply() external returns (uint256) envfree;
    function virtualShares() external returns (uint256) envfree;
    function managementFee() external returns (uint96) envfree;
    function balanceOf(address account) external returns (uint256) envfree;

    // `balanceOf` is summarized to a bounded value.
    function _.balanceOf(address account) external => summaryBalanceOf() expect(uint256);

    function _.realAssets() external => summaryRealAssets() expect(uint256);

    // Trick to be able to retrieve the value returned by the corresponding contract before it is called, without the value changing between the retrieval and the call.
    function _.canSendShares(address account) external => ghostCanSendShares(calledContract, account) expect(bool);
    function _.canReceiveShares(address account) external => ghostCanReceiveShares(calledContract, account) expect(bool);
    function _.canSendAssets(address account) external => ghostCanSendAssets(calledContract, account) expect(bool);
    function _.canReceiveAssets(address account) external => ghostCanReceiveAssets(calledContract, account) expect(bool);
}

ghost ghostCanSendShares(address, address) returns bool;

ghost ghostCanReceiveShares(address, address) returns bool;

ghost ghostCanSendAssets(address, address) returns bool;

ghost ghostCanReceiveAssets(address, address) returns bool;

function summaryBalanceOf() returns uint256 {
    uint256 balance;
    require balance < 2 ^ 128, "totalAssets is bounded by 2 ^ 128; vault balance is less than totalAssets";
    return balance;
}

// Returns a value bounded by 2^126.
// sum of realAssets of each adapter should be bounded by 2 ^ 128; Since loop_iter is 3, we bound each real assets by 2 ^ 126 to avoid overflow when summing them.
function summaryRealAssets() returns uint256 {
    uint256 realAssets;
    require realAssets < 2 ^ 126;
    return realAssets;
}

rule accrueInterestViewRevertCondition(env e) {
    require(e.msg.value == 0, "setup the call");
    require(e.block.timestamp >= currentContract.lastUpdate(), "block timestamps are guaranteed to be non-decreasing");
    require(totalSupply() < 10 ^ 35, "totalSupply is assumed to be less than 10 ^ 35");
    require(virtualShares() < 10 ^ 18, "virtualShares is bounded by 10 ^ 18");
    require(performanceFee() < Utils.maxPerformanceFee(), "see PerformanceFeeBound invariant in Invariants.spec; bounded by 0.5 * 10 ^ 18");
    require(managementFee() < Utils.maxManagementFee(), "see ManagementFeeBound invariant in Invariants.spec;  bounded by 0.05 * 10 ^ 18 / 365 days");
    require(e.block.timestamp - currentContract.lastUpdate() < 10 * 365 * 24 * 60 * 60, "current block timestamp should be < 10 years from lastUpdate");
    require(currentContract._totalAssets < 10 ^ 35, "totalAssets is bounded by 10 ^ 35");
    require(maxRate() < Utils.maxMaxRate(), "see maxRateBound invariant in Invariants.spec; maxRate is bounded by 2 * 10 ^ 18 / 365 days");

    uint256 newTotalAssets;
    uint256 performanceFeeShares;
    uint256 managementFeeShares;
    (newTotalAssets, performanceFeeShares, managementFeeShares) = accrueInterestView@withrevert(e);

    assert !lastReverted;
    assert newTotalAssets < 2 ^ 128;
    assert performanceFeeShares < 2 ^ 236;
    assert managementFeeShares < 2 ^ 236;
}

rule accrueInterestRevertCondition(env e) {
    require(e.msg.value == 0, "setup the call");
    require(e.block.timestamp >= currentContract.lastUpdate(), "block timestamps are guaranteed to be non-decreasing");
    require(totalSupply() < 10 ^ 35, "totalSupply is bounded by 10 ^ 35");
    require(virtualShares() <= 10 ^ 18, "see virtualSharesBound invariant in Invariants.spec; virtualShares is bounded by 10 ^ 18");
    require(performanceFee() < Utils.maxPerformanceFee(), "see PerformanceFeeBound invariant in Invariants.spec; bounded by 0.5 * 10 ^ 18");
    require(managementFee() < Utils.maxManagementFee(), "see ManagementFeeBound invariant in Invariants.spec;  bounded by 0.05 * 10 ^ 18 / 365 days");
    require(e.block.timestamp - currentContract.lastUpdate() < 10 * 365 * 24 * 60 * 60, "current block timestamp should be < 10 years from lastUpdate");
    require(currentContract._totalAssets < 2 ^ 116, "totalAssets is bounded by 10 ^ 35");
    require(maxRate() < Utils.maxMaxRate(), "see maxRateBound invariant in Invariants.spec; maxRate is bounded by 2 * 10 ^ 18 / 365 days");
    require(performanceFeeRecipient() != 0, "performance fee recipient should not be the zero address");
    require(managementFeeRecipient() != 0, "management fee recipient should not be the zero address");

    require(balanceOf(performanceFeeRecipient()) < 2 ^ 256 - 2 ^ 236, "balance of performance fee recipient should be less than 2 ^ 255 - max performanceFeeShare; see accrueInterestViewRevertCondition");
    require(balanceOf(managementFeeRecipient()) < 2 ^ 256 - 2 ^ 236, "balance of management fee recipient should be less than 2 ^ 255 - max managementFeeShare; see accrueInterestViewRevertCondition");

    accrueInterest@withrevert(e);

    assert !lastReverted;
}
