// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MetaMorphoV1_1 as vaultV1;

methods {
    function allocation() external returns (uint256) envfree;

    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => constantBorrowRate expect uint256;
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => constantBorrowRate expect uint256;

    // To remove because the asset should be linked to be ERC20Mock.
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function MetaMorphoV1_1.lastTotalAssets() external returns uint256 envfree;
    function MetaMorphoV1_1.balanceOf(address) external returns uint256 envfree;
    function MetaMorphoV1_1.totalSupply() external returns uint256 envfree;
    function MetaMorphoV1_1._accruedFeeAndAssets() internal returns (uint, uint, uint) => NONDET;
}

persistent ghost uint256 constantBorrowRate;

// Check that calling allocate or deallocate with 0 amount yields the same change.
rule sameChangeForAllocateAndDeallocateOnZeroAmount(env e, bytes data, bytes4 selector, address sender) {
  require(e.msg.sender == currentContract.parentVault, "Speed up prover. This is required in the code.");
  require(data.length == 0, "Speed up prover. This is required in the code.");
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  storage initialState = lastStorage;

  bytes32[] idsAllocate; int256 changeAllocate;
  idsAllocate, changeAllocate = allocate(e, data, 0, selector, sender) at initialState;

  bytes32[] idsDeallocate; int256 changeDeallocate;
  idsDeallocate, changeDeallocate = deallocate(e, data, 0, selector, sender) at initialState;

  assert changeAllocate == changeDeallocate;
}

// Check that allocate cannot return a change that would make the current allocation negative.
rule changeForAllocateIsBoundedByAllocation(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
  require(e.msg.sender == currentContract.parentVault, "Speed up prover. This is required in the code.");
  require(data.length == 0, "Speed up prover. This is required in the code.");
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  mathint allocation = allocation();

  bytes32[] ids; int256 change;
  ids, change = allocate(e, data, assets, selector, sender);

  require (vaultV1.balanceOf(currentContract) < vaultV1.totalSupply(), "total supply is the sum of the balance");
  require (vaultV1.lastTotalAssets() < 30 * 2^128, "market v1 stores assets on 128 bits, and there are at most 30 markets in vault v1");

  assert allocation + change >= 0;
}

// Check that deallocate cannot return a change that would make the current allocation negative.
rule changeForDeallocateIsBoundedByAllocation(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
  require(e.msg.sender == currentContract.parentVault, "Speed up prover. This is required in the code.");
  require(data.length == 0, "Speed up prover. This is required in the code.");
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  mathint allocation = allocation();

  bytes32[] ids; int256 change;
  ids, change = deallocate(e, data, assets, selector, sender);

  require (vaultV1.balanceOf(currentContract) < vaultV1.totalSupply(), "total supply is the sum of the balance");
  require (vaultV1.lastTotalAssets() < 30 * 2^128, "market v1 stores assets on 128 bits, and there are at most 30 markets in vault v1");

  assert allocation + change >= 0;
}
