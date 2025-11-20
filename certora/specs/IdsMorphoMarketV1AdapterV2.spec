// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "UtilityFunctions.spec";

using Utils as Utils;

methods {
    function adapterId() external returns (bytes32) envfree;
    function ids() external returns (bytes32[]) envfree;
    function morpho() external returns (address) envfree;
    function marketParams() external returns (MorphoMarketV1AdapterV2.MarketParams) envfree;  

    function Utils.havocAll() external envfree => HAVOC_ALL;
    function Utils.adapterId(address) external returns (bytes32) envfree;
    function Utils.marketV1Id(address) external returns (bytes32) envfree;
    function Utils.collateralTokenId(address) external returns (bytes32) envfree;
}

// Show that ids() always return the same thing. It will be used as the reference id list in other rules.
rule adapterAlwaysReturnsTheSameIDs() {
  bytes32[] idsPre = ids();

  Utils.havocAll();

  bytes32[] idsPost = ids();

  assert idsPre.length == idsPost.length;
  assert idsPre.length == 3;
  assert idsPre[0] == idsPost[0];
  assert idsPre[1] == idsPost[1];
  assert idsPre[2] == idsPost[2];
}

// Show that the ids returned on allocate or deallocate match the reference id list.
rule matchingIdsOnAllocateOrDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
  bytes32[] ids;
  ids, _ = allocateOrDeallocate(e, data, assets, selector, sender);

  bytes32[] idsMarket = ids();
  assert idsMarket.length == 3;
  assert ids.length == 3;
  assert ids[0] == idsMarket[0];
  assert ids[1] == idsMarket[1];
  assert ids[2] == idsMarket[2];
}

invariant valueOfMarketV1Id()
  ids()[0] == Utils.marketV1Id(morpho());

invariant valueOfCollateralTokenId()
  ids()[1] == Utils.collateralTokenId(marketParams().collateralToken);

invariant valueOfAdapterId()
  adapterId() == Utils.adapterId(currentContract);

rule distinctMarketV1Ids() {
  bytes32[] ids = ids();

  requireInvariant valueOfAdapterId();
  requireInvariant valueOfMarketV1Id();
  requireInvariant valueOfCollateralTokenId();

  assert forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i];
}
