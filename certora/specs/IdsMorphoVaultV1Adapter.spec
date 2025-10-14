// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "AdapterUtilityFunctions.spec";

using Utils as Utils;

methods {
    function ids() external returns (bytes32[]) envfree;

    function Utils.havocAll() external envfree => HAVOC_ALL;
}

// RUN : https://prover.certora.com/output/7508195/f4d1bc6f8a1f44359cbe1107bc42f733/?anonymousKey=6ea9658d5f304db8966ef02d60306229369f3abd

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
rule matchingIdsOnAllocateOrDeallocate(env e, bytes data, uint256 amount, bytes4 selector, address sender) {
  bytes32[] ids;

  bool isAllocate;
  ids, _ = allocate_or_deallocate(isAllocate, e, data, amount, selector, sender);

  bytes32[] idsAdapter = ids();
  assert idsAdapter.length == 1;
  assert ids.length == 1;
  assert ids[0] == idsAdapter[0];
}


