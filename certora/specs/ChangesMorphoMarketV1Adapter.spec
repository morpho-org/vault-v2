// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    // We need borrowRate and borrowRateView to return the same value
    // We don't know which IRM will be used, just assume 3% borrow rate for simplicity
    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);

    function allocation(Morpho.MarketParams) external returns (uint256) envfree;

    // To remove because the asset should be linked to be ERC20Mock.
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function Utils.decodeMarketParams(bytes) external returns (Morpho.MarketParams) envfree;
    function Utils.havocAll() external envfree => HAVOC_ALL;
}

// Check that from some starting state, calling allocate or deallocate with 0 amount yield the same change.
rule sameChangeForAllocateAndDeallocateOnZeroAmount(env e, bytes data, bytes4 selector, address sender) {
  require(e.msg.sender == currentContract.parentVault, "Speed up prover. This is required in the code.");
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
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
  mathint allocation = allocation(marketParams);

  bytes32[] ids; int256 change;
  ids, change = allocate(e, data, assets, selector, sender);

  assert allocation + change >= 0;
}

// Check that deallocate cannot return a change that would make the current allocation negative.
rule changeForDeallocateIsBoundedByAllocation(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
  require(e.msg.sender == currentContract.parentVault, "Speed up prover. This is required in the code.");
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
  mathint allocation = allocation(marketParams);

  bytes32[] ids; int256 change;
  ids, change = deallocate(e, data, assets, selector, sender);

  assert allocation + change >= 0;
}
