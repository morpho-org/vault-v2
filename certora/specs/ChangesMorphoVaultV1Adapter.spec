// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

using MorphoVaultV1Adapter as adapter;
using MetaMorphoV1_1 as metamorpho;
using VaultV2 as vaultv2;

methods {
    // We need borrowRate and borrowRateView to return the same value
    // We don't know which IRM will be used, just assume 3% borrow rate for simplicity
    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);

    function MetaMorphoV1_1.balanceOf(address) external returns (uint) envfree;
    // Summarize this so we limit the complexity and don't need to go in Morpho
    function MetaMorphoV1_1._accruedFeeAndAssets() internal returns (uint, uint, uint) => CONSTANT;
    // Summarize this so we limit the complexity and don't need to go in Morpho
    function MetaMorphoV1_1._accrueInterest() internal => CONSTANT;

    function Utils.havocAll() external envfree => HAVOC_ALL;
}

// Check that from some starting state, calling allocate or deallocate with 0 amount yield the same change.
rule sameChangeForAllocateAndDeallocate(env e, bytes data, bytes4 selector, address sender) {
  require(e.msg.sender == adapter.parentVault, "Speed up prover. This is required in the code.");
  require(data.length == 0, "Speed up prover. This is required in the code.");
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  storage initialState = lastStorage;

  bytes32[] idsAllocate; int256 changeAllocate;
  idsAllocate, changeAllocate = adapter.allocate(e, data, 0, selector, sender) at initialState;

  bytes32[] idsDeallocate; int256 changeDeallocate;
  idsDeallocate, changeDeallocate = adapter.deallocate(e, data, 0, selector, sender) at initialState;

  assert changeAllocate == changeDeallocate;
}

// Check that the adapter cannot return a loss that is bigger than its current allocation.
rule changeIsBoundedByAllocation() {
  env e;

  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(vaultv2.asset == metamorpho._asset, "Speed up prover.");

  bytes data;
  require(data.length == 0, "Speed up prover. The adapter requires empty data.");
  bytes4 selector;
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  address sender;
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  mathint allocation = adapter.allocation();

  uint256 amount; bytes32[] idsAllocate; int256 changeAllocate;
  idsAllocate, changeAllocate = adapter.allocate(e, data, amount, selector, sender);

  assert allocation + changeAllocate >= 0;
}
