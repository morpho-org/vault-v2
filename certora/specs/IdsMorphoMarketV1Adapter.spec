// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function Utils.havocAll() external envfree => HAVOC_ALL;
    function Utils.marketParamsToBytes(MorphoMarketV1Adapter.MarketParams) external returns(bytes) envfree;


    function ids(MorphoMarketV1Adapter.MarketParams) external returns (bytes32[]) envfree;
}

// Show that ids() is a function that only depend on its input. It will be used as the reference id list in other rules.
rule adapterAlwaysReturnsTheSameIDsForSameData(MorphoMarketV1Adapter.MarketParams marketParams) {
  bytes32[] idsPre = ids(marketParams);

  Utils.havocAll();

  bytes32[] idsPost = ids(marketParams);

  assert idsPre.length == idsPost.length;
  assert idsPre.length == 3;
  assert idsPre[0] == idsPost[0];
  assert idsPre[1] == idsPost[1];
  assert idsPre[2] == idsPost[2];
}

// Show that the ids returned on allocate match the refence id list.
rule matchingIdsOnAllocate(env e, uint256 amount, bytes4 selector, address sender) {
  MorphoMarketV1Adapter.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  bytes32[] idsAllocate; uint256 interestAllocate;
  idsAllocate, interestAllocate = allocate(e, data, amount, selector, sender);

  bytes32[] ids = ids(marketParams);
  assert ids.length == 3;
  assert idsAllocate.length == 3;
  assert idsAllocate[0] == ids[0];
  assert idsAllocate[1] == ids[1];
  assert idsAllocate[2] == ids[2];
}

// Show that the ids returned on deallocate match the refence id list.
rule matchingIdsOnDeallocate(env e, uint256 amount, bytes4 selector, address sender) {
  MorphoMarketV1Adapter.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  bytes32[] idsDeallocate; uint256 interestDeallocate;
  idsDeallocate, interestDeallocate = deallocate(e, data, amount, selector, sender);

  bytes32[] ids = ids(marketParams);
  assert ids.length == 3;
  assert idsDeallocate.length == 3;
  assert idsDeallocate[0] == ids[0];
  assert idsDeallocate[1] == ids[1];
  assert idsDeallocate[2] == ids[2];
}

// Show that the ids returned on realizeLoss match the refence id list.
rule matchingIdsOnRealizeLoss(env e, bytes4 selector, address sender) {
  MorphoMarketV1Adapter.MarketParams marketParams;
  bytes data = Utils.marketParamsToBytes(marketParams);
  bytes32[] idsRealizeLoss; uint256 interestRealizeLoss;
  idsRealizeLoss, interestRealizeLoss = realizeLoss(e, data, selector, sender);

  bytes32[] ids = ids(marketParams);
  assert ids.length == 3;
  assert idsRealizeLoss.length == 3;
  assert idsRealizeLoss[0] == ids[0];
  assert idsRealizeLoss[1] == ids[1];
  assert idsRealizeLoss[2] == ids[2];
}
