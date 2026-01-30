// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using Utils as Utils;

// This specification checks the revert conditions for the vault's allocate and deallocate.
// accrueInterest, safeTransfer and safeTransferFrom are assumed to not revert.

methods {
    function Utils.wad() external returns (uint256) envfree;
    function Utils.libMulDivDown(uint256 x, uint256 y, uint256 d) external returns (uint256) envfree;
    function firstTotalAssets() external returns (uint256) envfree;

    // Assume that accrueInterest does not revert.
    function accrueInterest() internal => NONDET;

    // Assume that SafeERC20Lib.safeTransfer does not revert.
    function SafeERC20Lib.safeTransfer(address token, address to, uint256 value) internal => NONDET;

    // Assume that SafeERC20Lib.safeTransferFrom does not revert.
    function SafeERC20Lib.safeTransferFrom(address token, address from, address to, uint256 value) internal => NONDET;

    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryDeallocate(e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAllocate(e, data, assets, selector, sender) expect(bytes32[], int256);
}

// Checks the post-conditions P required in the rule allocateRevertCondition.
function summaryAllocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    // Assume length 3 for simplicity. This covers MarketV1Adapter and the rule similarly holds for VaultV1Adapter with ids.length == 1.
    require ids.length == 3, "for simplicity, assume a fixed number of markets: 3";

    require ids[0] != ids[1], "specification requires adapters to return unique ids";
    require ids[0] != ids[2], "specification requires adapters to return unique ids";
    require ids[1] != ids[2], "specification requires adapters to return unique ids";

    require currentContract.firstTotalAssets() < 2 ^ 20 * 2 ^ 128, "market v1 fits total supply assets on 128 bits, and assume at most 2^20 markets";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].relativeCap < 2 ^ 108, "see relativeCapBound invariant";

    // CVL does not allow function calls within quantifiers, hence explicitly listed here.
    require(currentContract.caps[ids[0]].relativeCap == Utils.wad() || currentContract.caps[ids[0]].allocation + change <= Utils.libMulDivDown(currentContract.firstTotalAssets(), currentContract.caps[ids[0]].relativeCap, Utils.wad())), "assume allocation respects relative cap";
    require(currentContract.caps[ids[1]].relativeCap == Utils.wad() || currentContract.caps[ids[1]].allocation + change <= Utils.libMulDivDown(currentContract.firstTotalAssets(), currentContract.caps[ids[1]].relativeCap, Utils.wad())), "assume allocation respects relative cap";
    require(currentContract.caps[ids[2]].relativeCap == Utils.wad() || currentContract.caps[ids[2]].allocation + change <= Utils.libMulDivDown(currentContract.firstTotalAssets(), currentContract.caps[ids[2]].relativeCap, Utils.wad())), "assume allocation respects relative cap";

    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= 2 ^ 255 - 1, "see allocationIsInt256";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].absoluteCap > 0, "specification disallows allocating from an adapter if one of the absolute cap is zero";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0, "see changeForAllocateOrDeallocateIsBoundedByAllocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change <= currentContract.caps[ids[i]].absoluteCap, "assume updated allocation respects absolute cap";

    return (ids, change);
}

// Checks the post-conditions P required in the rule deallocateRevertCondition.
function summaryDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    // assume MarketV1Adapter. The rule similarly holds for VaultV1Adapter with ids.length == 1.
    require ids.length == 3, "for simplicity, assume a fixed number of markets: 3";

    require ids[0] != ids[1], "specification requires adapters to return unique ids";
    require ids[0] != ids[2], "specification requires adapters to return unique ids";
    require ids[1] != ids[2], "specification requires adapters to return unique ids";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "specification disallows deallocating from an adapter with zero allocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= 2 ^ 255 - 1, "see allocationIsInt256 invariant";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0, "see changeForAllocateOrDeallocateIsBoundedByAllocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change <= 2 ^ 255 - 1, "see allocationIsInt256 invariant";

    return (ids, change);
}

// We assume accrueInterest, SafeERC20Lib.safeTransfer and SafeERC20Lib.safeTransferFrom do not revert.
// The rule states a result of the form P => (Q <=> lastReverted), where
// P is the post-conditions for adapter's allocate to ensure Vault's allocate does not revert. Specifically, the adapter returns market ids such that:
// - market ids are unique, the proof is done on length 3 for simplicity.
// - each market's allocation respects its relative and absolute caps after accounting for the change in allocation due to the allocate call.
// - absoluteCap is positive for each id.
// Q are the revert conditions.
rule allocateRevertCondition(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    allocate@withrevert(e, adapter, data, assets);
    assert !callerIsAllocator || !adapterIsRegistered || e.msg.value != 0 <=> lastReverted;
}

// We assume accrueInterest, SafeERC20Lib.safeTransfer and SafeERC20Lib.safeTransferFrom do not revert.
// The rule states a result of the form P => (Q <=> lastReverted), where
// P is the post-conditions for adapter's deallocate to ensure Vault's deallocate does not revert. Specifically, the adapter returns market ids such that:
// - market ids are unique, the proof is done on length 3 for simplicity.
// - each market's allocation is positive
// Q are the revert conditions.
rule deallocateRevertCondition(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool callerIsSentinel = isSentinel(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    deallocate@withrevert(e, adapter, data, assets);
    assert !(callerIsAllocator || callerIsSentinel) || !adapterIsRegistered || e.msg.value != 0 <=> lastReverted;
}
