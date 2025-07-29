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

    function MorphoMarketV1Adapter.ids(MorphoMarketV1Adapter.MarketParams) external returns (bytes32[]) envfree;

    function Utils.marketParamsToBytes(MorphoMarketV1Adapter.MarketParams) external returns (bytes) envfree;
}


ghost bool queried_external;

hook CALL(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    queried_external = true;
}

hook CALLCODE(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    queried_external = true;
}

hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    queried_external = true;
}

hook DELEGATECALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    queried_external = true;
}

hook EXTCODECOPY(address addr, uint256 retOffset, uint256 codesOffset, uint256 codeSize) {
    queried_external = true;
}

/*
  - the result of ids() cannot be changed by another contract

  This allows us to limit the calls to methods of the adapters in rule adapterAlwaysReturnsTheSameIDsForSameData
  instead of calls over "_". We are guaranteed ids() only consumes local data.
*/
rule idsDoNoteRelyOnExternalCode {
  require(!queried_external);
  Morpho.MarketParams marketParams;
  adapter.ids(marketParams);
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
rule adapterAlwaysReturnsTheSameIDsForSameData(env e, method f, calldataarg args) filtered {
  f -> !f.isView
} {
  require(vaultv2.sharesGate == 0x0000000000000000000000000000000000000000, "to avoid the canSendShares dispatch loop");

  Morpho.MarketParams marketParams;
  bytes32[] idsPre = adapter.ids(marketParams);

  adapter.f(e, args);

  bytes32[] idsPost = adapter.ids(marketParams);

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
// Todo: do not assume 0 amount, and same environment for allocate and deallocate
rule adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate() {
  env e;
  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.morpho == morpho, "Fix morpho address.");

  Morpho.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  storage initialState = lastStorage;

  bytes32[] idsAllocate; uint256 interestAllocate;
  idsAllocate, interestAllocate = adapter.allocate(e, data, 0, b4, addr) at initialState;

  bytes32[] idsDeallocate; uint256 interestDeallocate;
  idsDeallocate, interestDeallocate = adapter.deallocate(e, data, 0, b4, addr) at initialState;

  assert interestAllocate == interestDeallocate;

  // IDs match on allocate and deallocate
  bytes32[] ids = adapter.ids(marketParams);
  assert ids.length == 3;

  assert idsDeallocate.length == ids.length;
  assert idsDeallocate[0] == ids[0];
  assert idsDeallocate[1] == ids[1];
  assert idsDeallocate[2] == ids[2];

  assert idsAllocate.length == ids.length;
  assert idsAllocate[0] == ids[0];
  assert idsAllocate[1] == ids[1];
  assert idsAllocate[2] == ids[2];
}

/*
  - from the same starting state, either realizeLoss() or allocate()/deallocate() return 0.
    The rule is done with allocate() but holds for deallocate() as well because we know they return the same interest for a given starting state (see adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate)
  - ids returned by realizeLoss are the same as the ids returned by ids()
*/
rule adapterCannotHaveInterestAndLossAtTheSameTime() {
  storage initial = lastStorage;
  env e;
  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.morpho == morpho, "Fix morpho address.");

  Morpho.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  bytes32[] idsAllocate; uint256 interest;
  idsAllocate, interest = adapter.allocate(e, data, 0, b4, addr) at initial;

  bytes32[] idsRealizeLoss; uint256 loss;
  idsRealizeLoss, loss = adapter.realizeLoss(e, data, b4, addr) at initial;

  assert loss == 0 || interest == 0;

  // IDs match on allocate and realizeLoss (and deallocate thanks to rule adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate)
  bytes32[] ids = adapter.ids(marketParams);

  assert idsRealizeLoss.length == 3;
  assert idsRealizeLoss[0] == ids[0];
  assert idsRealizeLoss[1] == ids[1];
  assert idsRealizeLoss[2] == ids[2];
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
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  bytes32[] ids = adapter.ids(marketParams);

  mathint allocation = vaultv2.caps[ids[2]].allocation;
  assert(allocation == adapter.allocation(e, marketParams));

  bytes32[] returnedIds; uint256 loss;
  returnedIds, loss = adapter.realizeLoss(e, data, b4, addr);

  assert loss <= allocation;
}

/*
  - donating some underlying position to the adapter has no effect on the interest returned.
    The rule is done with allocate() but holds for deallocate() as well because we know they return the same interest for a given starting state (see adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate)
*/
rule donatingPositionsHasNoEffectOnInterest() {
  env e1;
  env e2;
  require(e1.msg.sender == adapter.parentVault, "Speed up prover.");
  require(e2.block.timestamp <= e1.block.timestamp, "We first donate, then look for the interest");
  require(adapter.parentVault == vaultv2);
  require(vaultv2.sharesGate == 0x0000000000000000000000000000000000000000);
  require(adapter.morpho == mockMorpho, "Fix morpho address. Use mock for simplicity.");

  Morpho.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(e1, marketParams);
  uint256 amount;
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint256 interestNoGift;
  _, interestNoGift = adapter.allocate(e1, data, amount, b4, addr) at initial;

  uint256 donationAmount;
  bytes supplyData; require(supplyData.length == 0, "No callback for simplicity.");
  morpho.supply(e2, marketParams, donationAmount, 0, adapter, supplyData) at initial;// Donate to the adapter
  uint256 interestWithGift;
  _, interestWithGift = adapter.allocate(e1, data, amount, b4, addr);

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
  bytes data = Utils.marketParamsToBytes(e1, marketParams);
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint256 lossNoGift;
  _, lossNoGift = adapter.realizeLoss(e1, data, b4, addr) at initial;

  uint256 donationAmount;
  bytes supplyData; require(supplyData.length == 0, "No callback for simplicity.");
  morpho.supply(e2, marketParams, donationAmount, 0, adapter, supplyData) at initial;// Donate to the adapter
  uint256 lossWithGift;
  _, lossWithGift = adapter.realizeLoss(e1, data, b4, addr);

  assert lossNoGift == lossWithGift;
}
