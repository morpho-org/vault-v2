// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityAdapters.spec";

using Utils as Utils;

methods {
    function adapterId() external returns (bytes32) envfree;
    function ids(MorphoMarketV1AdapterV2.MarketParams) external returns (bytes32[]) envfree;

    function Utils.havocAll() external envfree => HAVOC_ALL;
    function Utils.adapterId(address) external returns (bytes32) envfree;
    function Utils.decodeMarketParams(bytes) external returns(MorphoMarketV1AdapterV2.MarketParams) envfree;
}

// Show that ids() is a function that only depend on its input. It will be used as the reference id list in other rules.
rule adapterAlwaysReturnsTheSameIDsForSameData(MorphoMarketV1AdapterV2.MarketParams marketParams) {
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
  MorphoMarketV1AdapterV2.MarketParams marketParams = Utils.decodeMarketParams(data);

  bytes32[] ids;
  ids, _ = allocateOrDeallocate(e, data, assets, selector, sender);

  bytes32[] idsMarket = ids(marketParams);
  assert idsMarket.length == 3;
  assert ids.length == 3;
  assert ids[0] == idsMarket[0];
  assert ids[1] == idsMarket[1];
  assert ids[2] == idsMarket[2];
}

invariant valueOfAdapterId()
  adapterId() == Utils.adapterId(currentContract);

rule distinctMarketV1Ids(MorphoMarketV1AdapterV2.MarketParams marketParams) {
  bytes32[] ids = ids(marketParams);

  requireInvariant valueOfAdapterId();

  assert forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i];
}
