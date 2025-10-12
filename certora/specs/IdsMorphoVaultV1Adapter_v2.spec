// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

//E RUN : https://prover.certora.com/output/7508195/d6392b5f4cc34478a46be0b5d6dbdb82/?anonymousKey=28e3c2d426a0254faa6ecdd9351cdd56c2ee89cd

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
rule matchingIdsOnAllocateOrDeallocate(env e, bytes data, uint256 amount, bytes4 selector, address sender) {
  bytes32[] ids;
  int256 interest;

  bool isAllocate;
  if (isAllocate) {
    ids, interest = allocate(e, data, amount, selector, sender);
  } else {
    ids, interest = deallocate(e, data, amount, selector, sender);
  }

  bytes32[] idsAdapter = ids();
  assert idsAdapter.length == 1;
  assert ids.length == 1;
  assert ids[0] == idsAdapter[0];
}


