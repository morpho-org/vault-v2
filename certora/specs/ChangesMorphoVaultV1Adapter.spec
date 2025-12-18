// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityAdapters.spec";

using MetaMorphoV1_1 as vaultV1;

methods {
    function allocation() external returns (uint256) envfree;
    function MetaMorphoV1_1.balanceOf(address) external returns (uint256) envfree;
    function MetaMorphoV1_1.totalSupply() external returns (uint256) envfree;

    // Needed because linking fails.
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function MetaMorphoV1_1._accruedFeeAndAssets() internal returns (uint256, uint256, uint256) => constantAccrueFeeAndAssets();

    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => CONSTANT;

    function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns (uint256) => mulDivSummary(x, y, denominator);
}

function mulDivSummary(uint256 x, uint256 y, uint256 denominator) returns uint256 {
    mathint result;
    if (denominator == 0) revert();
    result = x * y / denominator;
    if (result >= 2 ^ 256) revert();
    return assert_uint256(result);
}

persistent ghost uint256 constantFeeShares;

persistent ghost uint256 constantNewTotalAssets;

persistent ghost uint256 constantNewLostAssets;

function constantAccrueFeeAndAssets() returns (uint256, uint256, uint256) {
    require constantNewTotalAssets < 30 * 2 ^ 128, "market v1 stores assets on 128 bits, and there are at most 30 markets in vault v1";
    return (constantFeeShares, constantNewTotalAssets, constantNewLostAssets);
}

// Check that allocating or deallocating zero assets returns an equivalent allocation change.
rule sameChangeForAllocateAndDeallocateOnZeroAmount(env e, bytes data, bytes4 selector, address sender) {
    storage initialState = lastStorage;

    bytes32[] idsAllocate;
    int256 changeAllocate;
    idsAllocate, changeAllocate = allocate(e, data, 0, selector, sender);

    bytes32[] idsDeallocate;
    int256 changeDeallocate;
    idsDeallocate, changeDeallocate = deallocate(e, data, 0, selector, sender) at initialState;

    assert changeAllocate == changeDeallocate;
}

// Check that allocate cannot return a change that would make the current allocation negative.
rule changeForAllocateOrDeallocateIsBoundedByAllocation(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
    mathint allocation = allocation();

    bytes32[] ids;
    int256 change;
    ids, change = allocateOrDeallocate(e, data, assets, selector, sender);

    require vaultV1.balanceOf(currentContract) <= vaultV1.totalSupply(), "total supply is the sum of the balances";

    assert allocation + change >= 0;
}
