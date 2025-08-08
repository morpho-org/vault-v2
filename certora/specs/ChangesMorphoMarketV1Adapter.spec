// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as adapter;
using Utils as Utils;

methods {
    // We need borrowRate and borrowRateView to return the same value
    // We don't know which IRM will be used, just assume 3% borrow rate for simplicity
    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);

    function MorphoMarketV1Adapter.allocation(Morpho.MarketParams) external returns (uint256) envfree;

    function Utils.marketParamsToBytes(Morpho.MarketParams) external returns (bytes) envfree;
    function Utils.havocAll() external envfree => HAVOC_ALL;
}

// Check that from some starting state, calling allocate or deallocate with 0 amount yield the same change.
rule sameChangeForAllocateAndDeallocate(env e, bytes data, bytes4 selector, address sender) {
  require(e.msg.sender == adapter.parentVault, "Speed up prover. This is required in the code.");
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  storage initialState = lastStorage;

  bytes32[] idsAllocate; int256 changeAllocate;
  idsAllocate, changeAllocate = adapter.allocate(e, data, 0, selector, sender) at initialState;

  bytes32[] idsDeallocate; int256 changeDeallocate;
  idsDeallocate, changeDeallocate = adapter.deallocate(e, data, 0, selector, sender) at initialState;

  assert changeAllocate == changeDeallocate;
}

// Check that the adapter cannot return a change that would make the current allocation negative.
rule changeIsBoundedByAllocation() {
  env e;
  require(e.msg.sender == adapter.parentVault, "Speed up prover.");

  Morpho.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  bytes4 selector;
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  address sender;
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  mathint allocation = adapter.allocation(marketParams);

  uint256 amount; bytes32[] idsAllocate; int256 changeAllocate;
  idsAllocate, changeAllocate = adapter.allocate(e, data, amount, selector, sender);

  assert allocation + changeAllocate >= 0;
}
