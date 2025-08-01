// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function Utils.havocAll() external envfree => HAVOC_ALL;

    function ids() external returns (bytes32[]) envfree;
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

// Show that the ids returned on allocate match the refence id list.
rule matchingIdsOnAllocate(env e, bytes data, uint256 amount, bytes4 selector, address sender) {
  bytes32[] idsAllocate; uint256 interestAllocate;
  idsAllocate, interestAllocate = allocate(e, data, amount, selector, sender);

  bytes32[] ids = ids();
  assert ids.length == 1;
  assert idsAllocate.length == 1;
  assert idsAllocate[0] == ids[0];
}

// Show that the ids returned on deallocate match the refence id list.
rule matchingIdsOnDeallocate(env e, bytes data, uint256 amount, bytes4 selector, address sender) {
  bytes32[] idsDeallocate; uint256 interestDeallocate;
  idsDeallocate, interestDeallocate = deallocate(e, data, amount, selector, sender);

  bytes32[] ids = ids();
  assert ids.length == 1;
  assert idsDeallocate.length == 1;
  assert idsDeallocate[0] == ids[0];
}

// Show that the ids returned on realizeLoss match the refence id list.
rule matchingIdsOnRealizeLoss(env e, bytes data, bytes4 selector, address sender) {
  bytes32[] idsRealizeLoss; uint256 interestRealizeLoss;
  idsRealizeLoss, interestRealizeLoss = realizeLoss(e, data, selector, sender);

  bytes32[] ids = ids();
  assert ids.length == 1;
  assert idsRealizeLoss.length == 1;
  assert idsRealizeLoss[0] == ids[0];
}
