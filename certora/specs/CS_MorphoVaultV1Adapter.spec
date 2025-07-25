// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../summaries/IMorphoVaultV1Adapter.spec";
import "../summaries/IMetamorphoV1_1.spec";
import "../summaries/IMorpho.spec";

using MorphoVaultV1Adapter as adapter;
using MetaMorphoV1_1 as metamorpho;
using VaultV2 as vaultv2;
using Morpho as morpho;

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
rule idsDoNotRelyOnExternalCode {
  require(!queried_external);
  adapter.ids();
  /*
    If this fails, it means the contract is using external code to compute the ids,
    and thus calling f on the adapter only in adapterAlwaysReturnsTheSameIDsForSameData
    is not sufficient to be sure ids won't change.
  */
  assert !queried_external;
}

/*
  - ids() always return the same result for the same input data (in this case, input data is empty)
*/
rule adapterAlwaysReturnsTheSameIDsForSameData(method f) filtered {
  f -> !f.isView
} {
  env e;
  require(!queried_external);
  require(adapter.morphoVaultV1 == metamorpho, "Very important otherwise the same tokens might be accounted for twice.");
  require(metamorpho.MORPHO == morpho, "Fix morpho address.");
  require(adapter.parentVault == vaultv2, "We know the parent vault.");
  require(vaultv2.asset == metamorpho._asset, "We know the asset.");
  require(vaultv2.sharesGate == 0x0000000000000000000000000000000000000000);

  bytes32[] idsPre = adapter.ids();

  calldataarg args;
  adapter.f(e, args);

  bytes32[] idsPost = adapter.ids();

  assert idsPre.length == idsPost.length;
  assert idsPre.length == 1;
  assert idsPre[0] == idsPost[0];
}

/*
  - from some starting state, calling allocate or deallocate yield the same interest
  - ids match on allocate and deallocate
  - ids returned by allocate/deallocate are the same as the ids returned by ids()
*/
// Todo: do not assume 0 amount, and same environment for allocate and deallocate
rule adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate() {
  storage initialState = lastStorage;
  env e;
  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.parentVault == vaultv2, "Speed up prover.");
  require(adapter.morphoVaultV1 == metamorpho, "Speed up prover.");
  require(metamorpho.MORPHO == morpho, "Fix morpho address.");
  require(vaultv2.asset == metamorpho._asset, "Speed up prover.");

  bytes data;
  require(data.length == 0, "Speed up prover.");
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover.");

  bytes32[] idsAllocate; uint256 interestAllocate;
  idsAllocate, interestAllocate = adapter.allocate(e, data, 0, b4, addr) at initialState;

  bytes32[] idsDeallocate; uint256 interestDeallocate;
  idsDeallocate, interestDeallocate = adapter.deallocate(e, data, 0, b4, addr) at initialState;

  assert interestAllocate == interestDeallocate;

  // IDs match on allocate and deallocate
  bytes32[] ids = adapter.ids();

  assert idsAllocate.length == idsDeallocate.length;
  assert idsAllocate.length == 1;
  assert idsAllocate[0] == idsDeallocate[0];

  assert idsAllocate.length == ids.length;
  assert idsAllocate[0] == ids[0];
}

/*
  - from the same starting state, either realizeLoss() or allocate()/deallocate() return 0.
    The rule is done with allocate() but holds for deallocate() as well because we know they return the same interest for a given starting state (see adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate)
  - ids returned by realizeLoss are the same as the ids returned by ids() (and allocate()/deallocate())
  - ids returned by realizeLoss are the same as the ids returned by ids()
*/
rule adapterCannotHaveInterestAndLossAtTheSameTime() {
  env e;
  require(e.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.parentVault == vaultv2, "Speed up prover.");
  require(adapter.morphoVaultV1 == metamorpho, "Speed up prover.");
  require(metamorpho.MORPHO == morpho, "Fix morpho address.");
  require(vaultv2.asset == metamorpho._asset, "Speed up prover.");
  require(vaultv2.sharesGate == 0x0000000000000000000000000000000000000000);

  bytes data;
  require(data.length == 0, "Speed up prover. The adapter requires empty data.");
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  bytes32[] idsAllocate; uint256 interest;
  idsAllocate, interest = adapter.allocate(e, data, 0, b4, addr) at initial;

  bytes32[] idsRealizeLoss; uint256 loss;
  idsRealizeLoss, loss = adapter.realizeLoss(e, data, b4, addr) at initial;

  assert loss == 0 || interest == 0;

  // IDs match on allocate and realizeLoss (and deallocate thanks to rule adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate)
  bytes32[] ids = adapter.ids();

  assert idsRealizeLoss.length == 1;
  assert idsRealizeLoss[0] == ids[0];
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
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  bytes32[] ids = adapter.ids();

  mathint allocation = vaultv2.caps[ids[0]].allocation;
  assert(allocation == adapter.allocation(e));

  bytes32[] returnedIds; uint256 loss;
  returnedIds, loss = adapter.realizeLoss(e, data, b4, addr);

  assert loss <= allocation;
}

/*
  - donating some underlying position to the adapter has no effect on the interest returned.
    The rule is done with allocate() but holds for deallocate() as well because we know they return the same interest for a given starting state (see adapterReturnsTheSameInterestAndIdsForAllocateAndDeallocate)
*/
// Todo: show that amount don't change the interest.
rule donatingPositionsHasNoEffectOnInterest() {
  env e1;
  env e2;
  require(e1.msg.sender == adapter.parentVault, "Speed up prover.");
  require(e2.block.timestamp <= e1.block.timestamp, "We first donate, then look for the interest");
  require(adapter.parentVault == vaultv2);
  require(vaultv2.sharesGate == 0x0000000000000000000000000000000000000000);
  require(adapter.morphoVaultV1 == metamorpho, "Fix metamorpho address.");

  bytes data; require(data.length == 0, "Speed up prover. The adapter ignores this param.");
  bytes4 b4;
  require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr;
  require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  storage initial = lastStorage;

  uint256 interestNoGift;
  _, interestNoGift = adapter.allocate(e1, data, 0, b4, addr) at initial;

  uint256 donationAmount;
  metamorpho.transfer(e2, adapter, donationAmount) at initial;
  uint256 interestWithGift;
  _, interestWithGift = adapter.allocate(e1, data, 0, b4, addr);

  assert interestNoGift == interestWithGift;
}

/*
  - donating some underlying position to the adapter has no effect on the loss returned by realizeLoss()
*/
rule donatingPositionsHasNoEffectOnLoss() {
  env e1;
  require(e1.msg.sender == adapter.parentVault, "Speed up prover.");
  require(adapter.parentVault == vaultv2);
  require(vaultv2.sharesGate == 0x0000000000000000000000000000000000000000);
  require(adapter.morphoVaultV1 == metamorpho, "Speed up prover.");
  require(vaultv2.asset == metamorpho._asset, "Speed up prover.");

  bytes data; require(data.length == 0, "Speed up prover. The adapter ignores this param.");
  bytes4 b4; require(b4 == to_bytes4(0x00000000), "Speed up prover. The adapter ignores this param.");
  address addr; require(addr == 0x0000000000000000000000000000000000000000, "Speed up prover. The adapter ignores this param.");

  uint256 donation;

  storage initial = lastStorage;

  uint256 positionPre = metamorpho.balanceOf(adapter) at initial;
  require(metamorpho.balanceOf(adapter) == positionPre + donation); // Donate to the adapter, we don't use deposit as the prover times out
  storage initalWithDonation = lastStorage;
  uint256 positionPost = metamorpho.balanceOf(adapter) at initalWithDonation;
  assert(positionPost == positionPre + donation);

  uint256 interestNoGift;
  _, interestNoGift = adapter.allocate(e1, data, 0, b4, addr) at initial;


  uint256 interestWithGift;
  _, interestWithGift = adapter.allocate(e1, data, 0, b4, addr) at initalWithDonation;

  assert interestNoGift == interestWithGift;
}
