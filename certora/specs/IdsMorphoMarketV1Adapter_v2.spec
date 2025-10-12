// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

//E RUN : https://prover.certora.com/output/7508195/15ada4a7bb5344cba79c70011a462d4e/?anonymousKey=d9b9a31403689ce2ae3103fb395a1619f612dc97
 
using Utils as Utils;

methods {
    function ids(MorphoMarketV1Adapter.MarketParams) external returns (bytes32[]) envfree;

    function Utils.havocAll() external envfree => HAVOC_ALL;
    function Utils.decodeMarketParams(bytes) external returns(MorphoMarketV1Adapter.MarketParams) envfree;
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

// Show that the ids returned on allocate or deallocate match the reference id list.
rule matchingIdsOnAllocateOrDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
  MorphoMarketV1Adapter.MarketParams marketParams = Utils.decodeMarketParams(data);
  bytes32[] ids;
  int256 change;

  bool isAllocate;
  if (isAllocate) {
    ids, change = allocate(e, data, assets, selector, sender);
  } else {
    ids, change = deallocate(e, data, assets, selector, sender);
  }

  bytes32[] idsMarket = ids(marketParams);
  assert idsMarket.length == 3;
  assert ids.length == 3;
  assert ids[0] == idsMarket[0];
  assert ids[1] == idsMarket[1];
  assert ids[2] == idsMarket[2];
}


