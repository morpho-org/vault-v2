// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using MorphoHarness as MorphoMarketV1;
using RevertCondition as RevertCondition;

methods {

  function SafeERC20Lib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, executingContract, to, value);
  function _.balanceOf(address account) external => summaryBalanceOf(calledContract, account) expect(uint256) ALL;

  // Assume adaptiveIRM rate is not changed by skim.
  function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => constantBorrowRate expect(uint256);
}

ghost ghostBalanceOf(address, address) returns uint256;

persistent ghost mapping(address => uint256) adapterBalanceOf;

function summaryBalanceOf(address token, address account) returns uint256 {
    if (account == MorphoMarketV1AdapterV2) {
        return adapterBalanceOf[token];
    }
    return ghostBalanceOf(token, account);
}

function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == MorphoMarketV1AdapterV2) {
        // Safe require because the reference implementation would revert.
        adapterBalanceOf[token] = require_uint256(adapterBalanceOf[token] - amount);
    }
    if (to == MorphoMarketV1AdapterV2) {
        // Safe require because the reference implementation would revert.
        adapterBalanceOf[token] = require_uint256(adapterBalanceOf[token] + amount);
    }
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
