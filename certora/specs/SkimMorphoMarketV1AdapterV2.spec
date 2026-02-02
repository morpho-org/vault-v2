// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using MorphoHarness as MorphoMarketV1;
using VaultV2 as VaultV2;
using RevertCondition as RevertCondition;

methods {
  function VaultV2.curator() external returns (address) envfree;
  function MorphoMarketV1AdapterV2.skimRecipient() external returns (address) envfree;

  //assume safeTransfer does not revert.
  function SafeERC20Lib.safeTransfer(address, address, uint256) internal => NONDET;
  function _.balanceOf(address) external => DISPATCHER(true);

  function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => constantBorrowRate expect(uint256);

}

// assume adaptiveIRM rate is not changed by skim.
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
