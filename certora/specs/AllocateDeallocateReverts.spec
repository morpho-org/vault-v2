// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using Utils as Utils;

// This specification checks either the revert condition for the vault's allocate and deallocate.
// Interest accrual is assumed to not revert.

methods {
    function Utils.maxMaxRate() external returns (uint256) envfree;
    function Utils.wad() external returns (uint256) envfree;
    function Utils.libMulDivDown(uint256 x, uint256 y, uint256 d) external returns (uint256) envfree;
    function currentContract.firstTotalAssets() external returns (uint256) envfree;

    // Assume that accrueInterest does not revert.
    function accrueInterest() internal => NONDET;

    // Assume that SafeERC20Lib.safeTransferFrom does not revert.
    function SafeERC20Lib.safeTransfer(address token, address to, uint256 value) internal => NONDET;

    // Assume that SafeERC20Lib.safeTransferFrom does not revert.
    function SafeERC20Lib.safeTransferFrom(address token, address from, address to, uint256 value) internal => NONDET;

    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryDeallocate(e, data, assets, selector, sender) expect(bytes32[], int256);
    function _.allocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryAllocate(e, data, assets, selector, sender) expect(bytes32[], int256);
}

function summaryAllocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;
    require ids.length == 3, "see IdsMorphoMarketV1Adapter";

    require ids[0] != ids[1], "ack";
    require ids[0] != ids[2], "ack";
    require ids[1] != ids[2], "ack";

    // CVL does not allow function calls within quantifiers, hence explicitly listed here.
    require currentContract.firstTotalAssets() * currentContract.caps[ids[0]].relativeCap <= max_uint256, "assume firstTotalASsets is bounded by max_uint256/WAD";
    require currentContract.firstTotalAssets() * currentContract.caps[ids[1]].relativeCap <= max_uint256, "assume firstTotalASsets is bounded by max_uint256/WAD";
    require currentContract.firstTotalAssets() * currentContract.caps[ids[2]].relativeCap <= max_uint256, "assume firstTotalASsets is bounded by max_uint256/WAD";

    // CVL does not allow function calls within quantifiers, hence explicitly listed here.
    require(currentContract.caps[ids[0]].relativeCap == Utils.wad() || currentContract.caps[ids[0]].allocation + change <= Utils.libMulDivDown(currentContract.firstTotalAssets(), currentContract.caps[ids[0]].relativeCap, Utils.wad())), "assume allocation respects relative cap";
    require(currentContract.caps[ids[1]].relativeCap == Utils.wad() || currentContract.caps[ids[1]].allocation + change <= Utils.libMulDivDown(currentContract.firstTotalAssets(), currentContract.caps[ids[1]].relativeCap, Utils.wad())), "assume allocation respects relative cap";
    require(currentContract.caps[ids[2]].relativeCap == Utils.wad() || currentContract.caps[ids[2]].allocation + change <= Utils.libMulDivDown(currentContract.firstTotalAssets(), currentContract.caps[ids[2]].relativeCap, Utils.wad())), "assume allocation respects relative cap";

    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= 2 ^ 255 - 1, "assume allocation is small enough to cast to int256";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0, "see changeForAllocateOrDeallocateIsBoundedByAllocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change <= currentContract.caps[ids[i]].absoluteCap, "assume updated allocation respects absolute cap";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].absoluteCap > 0, "assume that the absolute cap is positive";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= currentContract.caps[ids[i]].absoluteCap, "assume allocation respects absolute cap";

    return (ids, change);
}

function summaryDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    // assume MarketV1Adapter. The rule similarly holds for VaultV1Adapter with ids.length == 1.
    require ids.length == 3, "see IdsMorphoMarketV1Adapter";

    require ids[0] != ids[1], "ack";
    require ids[0] != ids[2], "ack";
    require ids[1] != ids[2], "ack";

    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "assume that the allocation is positive";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation <= 2 ^ 255 - 1, "assume allocation is small enough to cast to int256";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change >= 0, "see changeForAllocateOrDeallocateIsBoundedByAllocation";
    require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation + change <= 2 ^ 255 - 1, "updating allocation reverts";

    return (ids, change);
}

rule allocateRevertCondition(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    allocate@withrevert(e, adapter, data, assets);
    assert !callerIsAllocator || !adapterIsRegistered || e.msg.value != 0 <=> lastReverted;
}

rule deallocateRevertCondition(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool callerIsSentinel = isSentinel(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    deallocate@withrevert(e, adapter, data, assets);
    assert !(callerIsAllocator || callerIsSentinel) || !adapterIsRegistered || e.msg.value != 0 <=> lastReverted;
}
