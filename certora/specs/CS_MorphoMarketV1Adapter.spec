// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

using MorphoMarketV1Adapter as adapter;
using Morpho as morpho;
using VaultV2 as vaultv2;
using CSMockMorpho as mockMorpho;

methods {
    // We need borrowRate and borrowRateView to return the same value
    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);// We don't know which IRM will be used, just assume 3% borrow rate for simplicity
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);// We don't know which IRM will be used, just assume 3% borrow rate for simplicity
    function _.onMorphoSupply(uint, bytes) external => NONDET DELETE;

    function MorphoMarketV1Adapter.ids(Morpho.MarketParams) external returns (bytes32[]) envfree;

    function Utils.marketParamsToBytes(Morpho.MarketParams) external returns (bytes) envfree;
    function Utils.havocAll() external envfree => HAVOC_ALL;
}

/*
  - from some starting state, calling allocate or deallocate yield the same interest
*/
rule adapterReturnsTheSameInterestForAllocateAndDeallocate(env e, bytes data, bytes4 selector, address sender) {
  require(e.msg.sender == adapter.parentVault, "Speed up prover. This is required in the code.");
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
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
  storage initial = lastStorage;
  env e;
  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.morpho == morpho, "Fix morpho address.");

  Morpho.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  bytes4 selector;
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  address sender;
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

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
  require(adapter.parentVault == vaultv2);
  require(adapter.morpho == morpho, "Fix morpho address.");

  Morpho.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  bytes4 selector;
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  address sender;
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  bytes32[] ids = adapter.ids(marketParams);

  mathint allocation = vaultv2.caps[ids[2]].allocation;
  assert(allocation == adapter.allocation(e, marketParams));

  bytes32[] returnedIds; uint256 loss;
  returnedIds, loss = adapter.realizeLoss(e, data, selector, sender);

  assert loss <= allocation;
}

/*
  - donating some underlying position to the adapter has no effect on the interest returned.
    The rule is done with allocate() but holds for deallocate() as well because we know they return the same interest for a given starting state (see adapterReturnsTheSameInterestAndForAllocateAndDeallocate)
*/
rule donatingPositionsHasNoEffectOnInterest() {
  env e1;
  env e2;
  require(e1.msg.sender == adapter.parentVault, "Speed up prover.");
  require(e2.block.timestamp <= e1.block.timestamp, "We first donate, then look for the interest");
  require(adapter.parentVault == vaultv2);
  require(adapter.morpho == mockMorpho, "Fix morpho address. Use mock for simplicity.");

  Morpho.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  uint256 amount;
  bytes4 selector;
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  address sender;
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint256 interestNoGift;
  _, interestNoGift = adapter.allocate(e1, data, amount, selector, sender) at initial;

  uint256 donationAmount;
  bytes supplyData; require(supplyData.length == 0, "No callback for simplicity.");
  morpho.supply(e2, marketParams, donationAmount, 0, adapter, supplyData) at initial;
  uint256 interestWithGift;
  _, interestWithGift = adapter.allocate(e1, data, amount, selector, sender);

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
  require(adapter.morpho == mockMorpho, "Fix morpho address. Use mock for simplicity.");

  Morpho.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  bytes4 selector;
  require(selector == to_bytes4(0), "Speed up prover. The adapter ignores this param.");
  address sender;
  require(sender == 0, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint256 lossNoGift;
  _, lossNoGift = adapter.realizeLoss(e1, data, selector, sender) at initial;

  uint256 donationAmount;
  bytes supplyData; require(supplyData.length == 0, "No callback for simplicity.");
  morpho.supply(e2, marketParams, donationAmount, 0, adapter, supplyData) at initial;
  uint256 lossWithGift;
  _, lossWithGift = adapter.realizeLoss(e1, data, selector, sender);

  assert lossNoGift == lossWithGift;
}
