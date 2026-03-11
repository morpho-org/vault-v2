// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function virtualShares() external returns (uint256) envfree;
    function performanceFeeRecipient() external returns (address) envfree;
    function managementFeeRecipient() external returns (address) envfree;

    // `balanceOf` is assumed to not revert and summarized to a bounded value.
    function _.balanceOf(address account) external => summaryBalanceOf() expect(uint256) ALL;

    // Adapter's `deallocate` is assumed to not revert when called and returns 3 distinct ids, with post-conditions on the returned ids and change as specified in summaryDeallocate.
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external => summaryDeallocate(data, assets, selector, sender) expect(bytes32[], int256);

    // `accrueInterest` is assumed to not revert; Check the rule accrueInterestRevertConditions in Reverts.spec.
    function accrueInterestView() internal returns (uint256, uint256, uint256) => summaryAccrueInterestView();

    // Trick to be able to retrieve the value returned by the corresponding contract before it is called, without the value changing between the retrieval and the call.
    function _.canSendShares(address account) external => ghostCanSendShares(calledContract, account) expect(bool);
    function _.canReceiveAssets(address account) external => ghostCanReceiveAssets(calledContract, account) expect(bool);
}

ghost ghostCanSendShares(address, address) returns bool;

ghost ghostCanReceiveAssets(address, address) returns bool;

// Maximum signed 256-bit integer, used to bound int256 return values.
definition max_int256() returns int256 = (2 ^ 255) - 1;

// Returns a value bounded by 10 ^ 35.
function summaryBalanceOf() returns uint256 {
    uint256 balance;
    require balance < 10 ^ 35, "totalAssets is assumed to be bounded by 10 ^ 35; vault balance is less than totalAssets";
    return balance;
}

// newTotalAssets returned by accrueInterestView is not proven to be < 10 ^ 35. We add it as an an explicit assumption required.
// In accrueInterestViewRevertConditions in AccrueInterestReverts.spec, we only show that the newTotalAssets is 2 ^ 128, given _totalAssets < 10 ^ 35.
// The bounds on performanceFeeShares and managementFeeShares are proven in the rule accrueInterestViewRevertConditions in Reverts.spec.
function summaryAccrueInterestView() returns (uint256, uint256, uint256) {
    uint256 newTotalAssets;
    uint256 performanceFeeShares;
    uint256 managementFeeShares;
    require newTotalAssets < 10 ^ 35, "totalAssets is bounded 10 ^ 35";
    require performanceFeeShares < 2 ^ 236, "see accrueInterestViewRevertConditions in Reverts.spec";
    require managementFeeShares < 2 ^ 236, "see accrueInterestViewRevertConditions in Reverts.spec";
    require(performanceFee() != 0 || performanceFeeShares == 0), "see accrueInterestViewRevertConditions in AccrueInterestReverts.spec";
    require(managementFee() != 0 || managementFeeShares == 0), "see accrueInterestViewRevertConditions in AccrueInterestReverts.spec";
    return (newTotalAssets, performanceFeeShares, managementFeeShares);
}

// Post-conditions on the adapter's deallocate required for the canForceDeallocateZero rule.
function summaryDeallocate(bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    // for simplicity, we assume the adapter returns exactly 3 ids.
    require ids.length == 3, "simplified adapter to return 3 ids";

    // the 3 returned ids must be pairwise distinct.
    require ids[0] != ids[1], "ids must be unique";
    require ids[0] != ids[2], "ids must be unique";
    require ids[1] != ids[2], "ids must be unique";

    // Post-conditions on the returned ids and change that ensures forceDeallocate with Zero does not revert:
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0;
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= max_int256();
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0;
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change <= max_int256();

    return (ids, change);
}

hook Sload uint256 balance balanceOf[KEY address addr] {
    require balance < 10 ^ 35, "balance is less than totalAssets and totalAssets is assume to bounded by 10 ^ 35";
}

strong invariant performanceFeeRecipientSetWhenPerformanceFeeIsSet()
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipientSetWhenManagementFeeIsSet()
    managementFee() != 0 => managementFeeRecipient() != 0;

// forceDeallocate with assets=0 triggers the adapter to update the allocation tracking in caps.
// We assume the asset token is ERC20Standard.
// This rule verifies the liveness property that `forceDeallocate()` can be called with assets=0 with the following pre-conditions:
//   1. The `onBehalf` address passes the sendShares gate check.
//   2. The vault itself passes the receiveAssets gate check.
//   3. totalSupply is bounded by 10 ^ 35.
//   4. Assumptions on the adapter's deallocate as specified in summaryDeallocate.
//   5. `accrueInterestView()` does not revert. See the accrueInterestViewRevertConditions for its revert conditions in AccrueInterestReverts.spec.
rule canForceDeallocateZero(env e, address adapter, bytes data, address onBehalf) {
    require totalSupply() < 10 ^ 35, "assume totalSupply is bounded by 10 ^ 35";

    // ensure that withdraw within forceDeallocate will not revert due to gates.
    require canSendShares(onBehalf), "onBehalf must pass canSendShares check";
    require canReceiveAssets(currentContract), "vault must pass canReceiveAssets check";

    // call set up
    require e.msg.value == 0, "forceDeallocate is non-payable";
    require isAdapter(adapter), "the adapter must be registered in the vault";
    require onBehalf != 0, "exit requires onBehalf to be non-zero address";

    // proven invariants
    requireInvariant performanceFeeRecipientSetWhenPerformanceFeeIsSet();
    requireInvariant managementFeeRecipientSetWhenManagementFeeIsSet();
    require virtualShares() <= 10 ^ 18, "See virtualSharesBounds in Invariants.spec";

    // call forceDeallocate with zero requested assets.
    forceDeallocate@withrevert(e, adapter, data, 0, onBehalf);

    assert !lastReverted;
}
