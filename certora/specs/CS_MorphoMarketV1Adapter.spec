// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../summaries/IMorpho.spec";

using MorphoMarketV1Adapter as adapter;
using Morpho as morpho;
using MorphoBlueUtils as MorphoBlueUtils;
using VaultV2 as vaultv2;
using CSMockMorpho as mockMorpho;

ghost bool queried_external;

hook CALL(uint g, address addr, uint value, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    queried_external = true;
}

hook CALLCODE(uint g, address addr, uint value, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    queried_external = true;
}

hook STATICCALL(uint g, address addr, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    queried_external = true;
}

hook DELEGATECALL(uint g, address addr, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    queried_external = true;
}

hook EXTCODECOPY(address addr, uint retOffset, uint codesOffset, uint codeSize) {
    queried_external = true;
}

/*
  - the result of ids() does not depend on the environment

  Special rule for MorphoMarketV1Adapter, as Certora doesn't manage to link the "ids()" method summary to the code for some reason.
  This is why "ids()" need the environment, but here we show env does not influence "ids()".
*/
rule idsDoNotRelyOnEnvironment {
  env e1;
  env e2;

  bytes32[] idsE1; bytes32[] idsE2;
  Morpho.MarketParams marketParams;
  idsE1 = adapter.ids(e1, marketParams);
  idsE2 = adapter.ids(e2, marketParams);

  assert idsE1.length == idsE2.length;
  assert idsE1.length == 3;
  assert idsE1[0] == idsE2[0];
  assert idsE1[1] == idsE2[1];
  assert idsE1[2] == idsE2[2];
}

/*
  - the result of ids() cannot be changed by another contract

  This allows us to limit the calls to methods of the adapters in rule adapterAlwaysReturnsTheSameIDsForSameData
  instead of calls over "_". We are guaranteed ids() only consumes local data.
*/
rule idsDoNoteRelyOnExternalCode {
  env e;
  require(!queried_external);
  Morpho.MarketParams marketParams;
  adapter.ids(e, marketParams);
  /*
    If this fails, it means the contract is using external code to compute the ids,
    and thus calling f on the adapter only in adapterAlwaysReturnsTheSameIDsForSameData
    is not sufficient to be sure ids won't change.
  */
  assert !queried_external;
}

/*
  - ids() always return the same result for the same input data (market params)
*/
rule adapterAlwaysReturnsTheSameIDsForSameData(method f) filtered {
  f -> !f.isView
} {
  env e;

  Morpho.MarketParams marketParams;
  bytes32[] idsPre = adapter.ids(e, marketParams);

  calldataarg args;
  adapter.f(e, args);

  bytes32[] idsPost = adapter.ids(e, marketParams);

  assert idsPre.length == idsPost.length;
  assert idsPre.length == 3;
  assert idsPre[0] == idsPost[0];
  assert idsPre[1] == idsPost[1];
  assert idsPre[2] == idsPost[2];
}

/*
  - from some starting state, calling allocate or deallocate yield the same interest
  - ids match on allocate and deallocate
  - ids returned by allocate/deallocate are the same as the ids returned by ids()
*/
rule adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate() {
  env e;
  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.morpho == morpho, "Fix morpho address.");

  Morpho.MarketParams marketParams;
  bytes data = MorphoBlueUtils.marketParamsToBytes(e, marketParams);
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  storage initialState = lastStorage;

  bytes32[] idsAllocate; uint interestAllocate;
  idsAllocate, interestAllocate = adapter.allocate(e, data, 0, b4, addr) at initialState;

  bytes32[] idsDeallocate; uint interestDeallocate;
  idsDeallocate, interestDeallocate = adapter.deallocate(e, data, 0, b4, addr) at initialState;

  assert interestAllocate == interestDeallocate;

  // IDs match on allocate and deallocate
  bytes32[] ids = adapter.ids(e, marketParams);

  assert idsAllocate.length == idsDeallocate.length;
  assert idsAllocate.length == 3;
  assert idsAllocate[0] == idsDeallocate[0];
  assert idsAllocate[1] == idsDeallocate[1];
  assert idsAllocate[2] == idsDeallocate[2];

  assert idsAllocate.length == ids.length;
  assert idsAllocate[0] == ids[0];
  assert idsAllocate[1] == ids[1];
  assert idsAllocate[2] == ids[2];
}

/*
  - from the same starting state, if realizeLoss() returns a non-zero value then allocate()/deallocate() must return 0
    the rule is done with allocate() but holds for deallocate() as well because we know they return the same interest
    for a given starting state (see adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate)
  - from the same starting state, if allocate()/deallocate() returns a non-zero value then realizeLoss() must return 0
    the rule is done with allocate() but holds for deallocate() as well because we know they return the same interest
    for a given starting state (see adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate)
  - ids returned by realizeLoss are the same as the ids returned by ids() (and allocate()/deallocate())
*/
rule adapterCannotHaveInterestAndLossAtTheSameTime() {
  storage initial = lastStorage;
  env e;
  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.morpho == morpho, "Fix morpho address.");

  Morpho.MarketParams marketParams;
  bytes data = MorphoBlueUtils.marketParamsToBytes(e, marketParams);
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  bytes32[] idsAllocate; uint interest;
  idsAllocate, interest = adapter.allocate(e, data, 0, b4, addr) at initial;

  bytes32[] idsRealizeLoss; uint loss;
  idsRealizeLoss, loss = adapter.realizeLoss(e, data, b4, addr) at initial;

  // If we have a loss, there must be 0 interest
  assert loss != 0 => interest == 0;
  // If we have some interest, there must be no loss
  assert interest != 0 => loss == 0;

  // IDs match on allocate and realizeLoss (and deallocate thanks to rule adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate)
  bytes32[] ids = adapter.ids(e, marketParams);

  assert idsAllocate.length == idsRealizeLoss.length;
  assert idsAllocate.length == 3;
  assert idsAllocate[0] == idsRealizeLoss[0];
  assert idsAllocate[1] == idsRealizeLoss[1];
  assert idsAllocate[2] == idsRealizeLoss[2];

  assert idsAllocate.length == ids.length;
  assert idsAllocate[0] == ids[0];
  assert idsAllocate[1] == ids[1];
  assert idsAllocate[2] == ids[2];
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
  bytes data = MorphoBlueUtils.marketParamsToBytes(e, marketParams);
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  bytes32[] ids = adapter.ids(e, marketParams);

  mathint allocation = vaultv2.caps[ids[2]].allocation;
  assert(allocation == adapter.allocation(e, marketParams));

  bytes32[] returnedIds; uint loss;
  returnedIds, loss = adapter.realizeLoss(e, data, b4, addr);

  assert loss <= allocation;
}

/*
  - donating some underlying position to the adapter has no effect on the interest returned by allocate()
*/
rule donatingPositionsHasNoEffectOnInterestFromAllocate() {
  env e1;
  env e2;
  require(e1.msg.sender == adapter.parentVault, "Speed up prover.");
  require(e2.block.timestamp <= e1.block.timestamp, "We first donate, then look for the interest");
  require(adapter.parentVault == vaultv2);
  require(vaultv2.sharesGate == 0x0000000000000000000000000000000000000000);
  require(adapter.morpho == mockMorpho, "Fix morpho address. Use mock for simplicity.");

  Morpho.MarketParams marketParams;
  bytes data = MorphoBlueUtils.marketParamsToBytes(e1, marketParams);
  uint amount;
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint interestNoGift;
  _, interestNoGift = adapter.allocate(e1, data, amount, b4, addr) at initial;

  uint donationAmount;
  bytes supplyData; require(supplyData.length == 0, "No callback for simplicity.");
  morpho.supply(e2, marketParams, donationAmount, 0, adapter, supplyData) at initial;// Donate to the adapter
  uint interestWithGift;
  _, interestWithGift = adapter.allocate(e1, data, amount, b4, addr);

  assert interestNoGift == interestWithGift;
}

/*
  - donating some underlying position to the adapter has no effect on the interest returned by deallocate()
*/
rule donatingPositionsHasNoEffectOnInterestFromDeallocate() {
  env e1;
  env e2;
  require(e1.msg.sender == adapter.parentVault, "Speed up prover.");
  require(e2.block.timestamp <= e1.block.timestamp, "We first donate, then look for the interest");
  require(adapter.parentVault == vaultv2);
  require(vaultv2.sharesGate == 0x0000000000000000000000000000000000000000);
  require(adapter.morpho == mockMorpho, "Fix morpho address. Use mock for simplicity.");

  Morpho.MarketParams marketParams;
  bytes data = MorphoBlueUtils.marketParamsToBytes(e1, marketParams);
  uint amount;
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint interestNoGift;
  _, interestNoGift = adapter.deallocate(e1, data, amount, b4, addr) at initial;

  uint donationAmount;
  bytes supplyData; require(supplyData.length == 0, "No callback for simplicity.");
  morpho.supply(e2, marketParams, donationAmount, 0, adapter, supplyData) at initial;// Donate to the adapter
  uint interestWithGift;
  _, interestWithGift = adapter.deallocate(e1, data, amount, b4, addr);

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
  require(vaultv2.sharesGate == 0x0000000000000000000000000000000000000000);
  require(adapter.morpho == mockMorpho, "Fix morpho address. Use mock for simplicity.");

  Morpho.MarketParams marketParams;
  bytes data = MorphoBlueUtils.marketParamsToBytes(e1, marketParams);
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint lossNoGift;
  _, lossNoGift = adapter.realizeLoss(e1, data, b4, addr) at initial;

  uint donationAmount;
  bytes supplyData; require(supplyData.length == 0, "No callback for simplicity.");
  morpho.supply(e2, marketParams, donationAmount, 0, adapter, supplyData) at initial;// Donate to the adapter
  uint lossWithGift;
  _, lossWithGift = adapter.realizeLoss(e1, data, b4, addr);

  assert lossNoGift == lossWithGift;
}
