// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using ERC20Standard as token;

methods {
    function virtualShares() external returns (uint256) envfree;
    function lastUpdate() external returns (uint64) envfree;

    // assume safeTransfer and safeTransferFrom do not revert.
    //function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    //function SafeERC20Lib.safeTransfer(address, address, uint256) internal => NONDET;
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.transfer(address, uint256) external => DISPATCHER(true);

    // `balanceOf` is summarized to a bounded value.
    function _.balanceOf(address account) external => summaryBalanceOf() expect(uint256) ALL;

    // `deallocate` is the core adapter callback. It is summarized with structural constraints from the MorphoMarketV1AdapterV2 implementation;
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryDeallocate(e, data, assets, selector, sender) expect(bytes32[], int256);

    // `realAssets` is summarized to a bounded value; see summaryRealAssets.
    function _.realAssets() external => summaryRealAssets() expect(uint256) ALL;

    // Trick to be able to retrieve the value returned by the corresponding contract before it is called, without the value changing between the retrieval and the call.
    function _.canSendShares(address account) external => ghostCanSendShares(calledContract, account) expect(bool);
    function _.canReceiveAssets(address account) external => ghostCanReceiveAssets(calledContract, account) expect(bool);
    function _.canReceiveShares(address account) external => ghostCanReceiveShares(calledContract, account) expect(bool);
}

ghost ghostCanSendShares(address, address) returns bool;

ghost ghostCanReceiveAssets(address, address) returns bool;

ghost ghostCanReceiveShares(address, address) returns bool;

// Maximum signed 256-bit integer, used to bound int256 return values.
definition max_int256() returns int256 = (2 ^ 255) - 1;

// Returns a value bounded by 2^128.
function summaryBalanceOf() returns uint256 {
    uint256 balance;
    require balance < 2 ^ 128, "totalAssets is bounded by 2 ^ 128; vault balance is less than totalAssets";
    return balance;
}

// Returns a value bounded by 2^128
function summaryRealAssets() returns uint256 {
    uint256 realAssets;
    require realAssets < 2 ^ 128, "totalAssets is bounded by 2 ^ 128; realAssets from each adater is less than totalAssets";
    return realAssets;
}

// This summary models the post-conditions of the adapter's deallocate which are required for the canForceDallocateZero rule to hold.
function summaryDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    // for simplicity, we assume the adapter returns exactly 3 ids.
    require ids.length == 3, "simplified adapter to return 3 ids";

    // the 3 returned market ids must be pairwise distinct.
    require ids[0] != ids[1], "ids must be unique";
    require ids[0] != ids[2], "ids must be unique";
    require ids[1] != ids[2], "ids must be unique";

    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "specification disallows deallocating from an adapter with zero allocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= 2 ^ 255 - 1, "see allocationIsInt256 invariant";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0, "see changeForAllocateOrDeallocateIsBoundedByAllocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change <= 2 ^ 255 - 1, "see allocationIsInt256 invariant";

    return (ids, change);
}

// forceDeallocate with assets=0 triggers the adapter to update the allocation tracking in caps.
// This rule verifies the liveness property that `forceDeallocate()` can be called with assets=0 with the following pre-conditions:
//   1. The `onBehalf` address passes the sendShares gate check.
//   2. The vault itself passes the receiveAssets gate check.
//   3. Total shares do not overflow uint256 when virtual shares are included.
//   4. Interest has already been accrued at the vault level for this block (i.e. lastUpdate == block.timestamp).
rule canForceDeallocateZero(env e, address adapter, bytes data, address onBehalf) {

    // the adapter must be registered in the vault.
    require isAdapter(adapter), "setup the call";

    // forceDeallocate is non-payable.
    require e.msg.value == 0, "setup the call";

    // gate checks that withdraw within forceDeallocate will not revert.
    require canSendShares(onBehalf);
    require canReceiveAssets(currentContract);

    // prevent totalSupply + virtualShares from overflowing, which would cause an arithmetic revert.
    require totalSupply() + virtualShares() <= max_uint256;

    require totalSupply() < 2 ^ 128;

    // vault's exit logic requires onBehalf to be non-zero address.
    require(onBehalf != 0, "setup the call");
    require(currentContract.asset != currentContract, "setup the call");
    require(currentContract.asset == token, "setup the call");
    //require(extcodesize(currentContract.asset) > 0, "setup the call");
    // interest must have been accrued for this block so that the vault's internal lastUpdate matches the current timestamp.
    // this is a fair assumption because accrueInterest() can be called permissionlessly.
    require(currentContract.lastUpdate() <= e.block.timestamp, "assume interest has been accrued at the Vault level");
    require(currentContract.virtualShares() < 2 ^ 64, "virtual shares are bounded by totalAssets, which is bounded by 2^128");
    require(e.block.timestamp < 2 ^ 64, "timestamps are currently less than 2^64");
    require(e.block.timestamp - currentContract.lastUpdate() < 31556926, "current block timestamp should be <10 years from lastUpdate");

    // call forceDeallocate with zero requested assets.
    forceDeallocate@withrevert(e, adapter, data, 0, onBehalf);

    assert !lastReverted;
}
