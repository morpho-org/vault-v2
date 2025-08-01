// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

using MorphoVaultV1Adapter as adapter;
using MetaMorphoV1_1 as metamorpho;
using VaultV2 as vaultv2;
using Morpho as morpho;

methods {
    // We need borrowRate and borrowRateView to return the same value
    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);// We don't know which IRM will be used, just assume 3% borrow rate for simplicity
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);// We don't know which IRM will be used, just assume 3% borrow rate for simplicity

    function MetaMorphoV1_1.balanceOf(address) external returns (uint) envfree;
    function MetaMorphoV1_1._accruedFeeAndAssets() internal returns (uint, uint, uint) => CONSTANT;// Summarize this so we limit the complexity and don't need to go in Morpho
    function MetaMorphoV1_1._accrueInterest() internal => CONSTANT;// Summarize this so we limit the complexity and don't need to go in Morpho

    function Utils.havocAll() external envfree => HAVOC_ALL;

    function ids() external returns (bytes32[]) envfree;
}

/*
  - from some starting state, calling allocate or deallocate yield the same interest
*/
rule adapterReturnsTheSameInterestForAllocateAndDeallocate(env e, bytes data, bytes4 selector, address sender) {
  require(e.msg.sender == adapter.parentVault, "Speed up prover. This is required in the code.");
  require(data.length == 0, "Speed up prover. This is required in the code.");
  require(selector == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  storage initialState = lastStorage;

  uint256 amountAllocate; bytes32[] idsAllocate; uint256 interestAllocate;
  idsAllocate, interestAllocate = adapter.allocate(e, data, amountAllocate, selector, sender) at initialState;

  uint256 amountDeallocate; bytes32[] idsDeallocate; uint256 interestDeallocate;
  idsDeallocate, interestDeallocate = adapter.deallocate(e, data, amountDeallocate, selector, sender) at initialState;

  assert interestAllocate == interestDeallocate;
}

/*
  - from the same starting state, either realizeLoss() or allocate()/deallocate() return 0.
    The rule is done with allocate() but holds for deallocate() as well because we know they return the same interest for a given starting state (see adapterReturnsTheSameInterestForAllocateAndDeallocate)
*/
rule adapterCannotHaveInterestAndLossAtTheSameTime() {
  env e;
  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.parentVault == vaultv2, "Speed up prover.");
  require(adapter.morphoVaultV1 == metamorpho, "Speed up prover.");
  require(metamorpho.MORPHO == morpho, "Fix morpho address.");
  require(vaultv2.asset == metamorpho._asset, "Speed up prover.");

  bytes data;
  require(data.length == 0, "Speed up prover. The adapter requires empty data.");
  bytes4 selector;
  require(selector == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address sender;
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  bytes32[] idsAllocate; uint256 interest;
  idsAllocate, interest = adapter.allocate(e, data, 0, selector, sender) at initial;

  bytes32[] idsRealizeLoss; uint256 loss;
  idsRealizeLoss, loss = adapter.realizeLoss(e, data, selector, sender) at initial;

  assert loss == 0 || interest == 0;
}

/*
  - the adapter cannot return a loss that is bigger than its current allocation
*/
rule lossIsBoundedByAllocation() {
  env e;

  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.parentVault == vaultv2, "Speed up prover.");
  require(adapter.morphoVaultV1 == metamorpho, "Speed up prover.");
  require(metamorpho.MORPHO == morpho, "Fix morpho address.");
  require(vaultv2.asset == metamorpho._asset, "Speed up prover.");

  bytes data;
  require(data.length == 0, "Speed up prover. The adapter requires empty data.");
  bytes4 selector;
  require(selector == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address sender;
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  bytes32[] ids = adapter.ids();

  mathint allocation = vaultv2.caps[ids[0]].allocation;
  assert(allocation == adapter.allocation(e));

  bytes32[] returnedIds; uint256 loss;
  returnedIds, loss = adapter.realizeLoss(e, data, selector, sender);

  assert loss <= allocation;
}

/*
  - donating some underlying position to the adapter has no effect on the interest returned.
    The rule is done with allocate() but holds for deallocate() as well because we know they return the same interest for a given starting state (see adapterReturnsTheSameInterestForAllocateAndDeallocate)
*/
// Todo: show that amount don't change the interest.
rule donatingPositionsHasNoEffectOnInterest() {
  env e1;
  env e2;
  require(e1.msg.sender == adapter.parentVault, "Speed up prover.");
  require(e2.block.timestamp <= e1.block.timestamp, "We first donate, then look for the interest");
  require(adapter.parentVault == vaultv2);
  require(adapter.morphoVaultV1 == metamorpho, "Fix metamorpho address.");

  bytes data; require(data.length == 0, "Speed up prover. The adapter ignores this param.");
  bytes4 selector;
  require(selector == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address sender;
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint256 interestNoGift;
  _, interestNoGift = adapter.allocate(e1, data, 0, selector, sender) at initial;

  uint256 donationAmount;
  metamorpho.transfer(e2, adapter, donationAmount) at initial;
  uint256 interestWithGift;
  _, interestWithGift = adapter.allocate(e1, data, 0, selector, sender);

  assert interestNoGift == interestWithGift;
}

/*
  - donating some underlying position to the adapter has no effect on the loss returned by realizeLoss()
*/
rule donatingPositionsHasNoEffectOnLoss() {
  env e1;
  env e2;
  require(e1.msg.sender == adapter.parentVault, "Speed up prover.");
  require(e2.block.timestamp <= e1.block.timestamp, "We first donate, then look for the interest");
  require(adapter.parentVault == vaultv2);
  require(adapter.morphoVaultV1 == metamorpho, "Speed up prover.");
  require(vaultv2.asset == metamorpho._asset, "Speed up prover.");

  bytes data; require(data.length == 0, "Speed up prover. The adapter ignores this param.");
  bytes4 selector; require(selector == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address sender; require(sender == 0, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint256 interestNoGift;
  _, interestNoGift = adapter.allocate(e1, data, 0, selector, sender) at initial;

  uint256 donationAmount;
  uint256 positionPre = metamorpho.balanceOf(adapter) at initial;
  metamorpho.transfer(e2, adapter, donationAmount) at initial;
  assert(metamorpho.balanceOf(adapter) == positionPre + donationAmount);
  uint256 interestWithGift;
  _, interestWithGift = adapter.allocate(e1, data, 0, selector, sender) at initial;

  assert interestNoGift == interestWithGift;
}
