// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

using MorphoHarness as MorphoMarketV1;
using RevertCondition as RevertCondition;

methods {

  function SafeERC20Lib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, executingContract, to, value);
  function _.balanceOf(address account) external => summaryBalanceOf(calledContract, account) expect(uint256);

  // Assume adaptiveIRM rate is not changed by skim.
  function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => constantBorrowRate expect(uint256);
}

ghost ghostBalanceOf(address, address) returns uint256;

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
