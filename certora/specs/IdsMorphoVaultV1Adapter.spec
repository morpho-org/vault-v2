// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "UtilityFunctions.spec";

using Utils as Utils;

methods {
    function ids() external returns (bytes32[]) envfree;

    function Utils.havocAll() external envfree => HAVOC_ALL;
}

// Show that ids() is a constant function. It will be used as the reference id list in other rules.
rule adapterAlwaysReturnsTheSameIDsForSameData() {
  bytes32[] idsPre = ids();

  Utils.havocAll();

  bytes32[] idsPost = ids();

  assert idsPre.length == idsPost.length;
  assert idsPre.length == 1;
  assert idsPre[0] == idsPost[0];
}

// Show that the ids returned on allocate or deallocate match the reference id list.
rule matchingIdsOnAllocateOrDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
  bytes32[] ids;

  bool isAllocate;
  ids, _ = allocateOrDeallocate(isAllocate, e, data, assets, selector, sender);

  bytes32[] idsAdapter = ids();
  assert idsAdapter.length == 1;
  assert ids.length == 1;
  assert ids[0] == idsAdapter[0];
}

// Show that the ids returned are distinct (trivial since there is only one id).
rule distinctAdapterIds() {
  bytes32[] ids = ids();

  assert forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i];
}
