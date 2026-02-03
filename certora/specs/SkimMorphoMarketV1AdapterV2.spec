// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

using MorphoHarness as MorphoMarketV1;
using RevertCondition as RevertCondition;

methods {
  //assume safeTransfer does not revert.
  function SafeERC20Lib.safeTransfer(address, address, uint256) internal => NONDET;
  function _.balanceOf(address) external => DISPATCHER(true);

  // Assume adaptiveIRM rate is not changed by skim.
  function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => constantBorrowRate expect(uint256);
}

persistent ghost uint256 constantBorrowRate;

rule skimDoesNotAffectAccountingMarketV1Adapter(env e, address token) {
  uint256 realAssetsBefore = realAssets(e);

  skim(e, token);

  uint256 realAssetsAfter = realAssets(e);
  assert realAssetsAfter == realAssetsBefore;
}

rule setSkimRecipientRevertConditionMarketV1Adapter(env e, address newRecipient) {
  bool revertCondition = RevertCondition.setSkimRecipient(e, newRecipient);

  setSkimRecipient@withrevert(e, newRecipient);

  assert revertCondition <=> lastReverted;
}
