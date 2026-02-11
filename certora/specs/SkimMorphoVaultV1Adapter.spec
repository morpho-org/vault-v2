// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using VaultV2 as VaultV2;
using MetaMorphoHarness as MorphoVaultV1;
using Utils as Utils;

methods {
  function VaultV2.owner() external returns (address) envfree;
  function Utils.id(MetaMorphoHarness.MarketParams) external returns(MetaMorphoHarness.Id) envfree;

  // Summaries.
  function _.expectedSupplyAssets(MorphoHarness.MarketParams marketParams, address user) external => summaryExpectedSupplyAssets(marketParams, user) expect (uint256);
  function _.idToMarketParams(MetaMorphoHarness.Id id) external => summaryIdToMarketParams(id) expect MetaMorphoHarness.MarketParams ALL;

  function SafeERC20Lib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, executingContract, to, value);
  function _.balanceOf(address account) external => ghostBalanceOf(calledContract, account) expect(uint256);
}

ghost ghostBalanceOf(address, address) returns uint256;

persistent ghost mapping(address => mathint) balance {
    init_state axiom (forall address token. balance[token] == 0);
}

ghost ghostExpectedSupply(address, address, address, address, uint256, address) returns uint256;

function summaryExpectedSupplyAssets(MorphoHarness.MarketParams marketParams, address user) returns uint256 {
    return ghostExpectedSupply(marketParams.loanToken, marketParams.collateralToken, marketParams.oracle, marketParams.irm, marketParams.lltv, user);
}

function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == MorphoVaultV1Adapter) {
        // Safe require because the reference implementation would revert.
        balance[token] = require_uint256(balance[token] - amount);
    }
    if (to == MorphoVaultV1Adapter) {
        // Safe require because the reference implementation would revert.
        balance[token] = require_uint256(balance[token] + amount);
    }
}

function summaryIdToMarketParams(MetaMorphoHarness.Id id) returns MetaMorphoHarness.MarketParams {
    MetaMorphoHarness.MarketParams marketParams;

    // We assume the marketd interacted with is created and present in the mapping.
    require (Utils.id(marketParams) == id, "see hashOfMarketParamsOf in Morpho-Blue ConsistentState.spec");

    return marketParams;
}

rule skimDoesNotAffectAccountingVaultV1Adapter(env e, address token) {
  uint256 realAssetsBefore = MorphoVaultV1Adapter.realAssets(e);

  MorphoVaultV1Adapter.skim(e, token);

  uint256 realAssetsAfter = MorphoVaultV1Adapter.realAssets(e);
  assert realAssetsAfter == realAssetsBefore;
}

rule setSkimRecipientRevertConditionVaultV1Adapter(env e, address newRecipient) {
  bool senderIsVaultOwner = e.msg.sender == VaultV2.owner();
  bool valueIsNonZero = e.msg.value == 0;

  MorphoVaultV1Adapter.setSkimRecipient@withrevert(e, newRecipient);

  assert !senderIsVaultOwner || !valueIsNonZero <=> lastReverted;
}
