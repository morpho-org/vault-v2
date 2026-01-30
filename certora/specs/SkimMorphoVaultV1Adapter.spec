// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using MetaMorphoHarness as MorphoVaultV1;

methods {

  function MorphoVaultV1Adapter.skimRecipient() external returns (address) envfree;
  function _.expectedSupplyAssets(MorphoHarness.MarketParams marketParams, address user) external => summaryExpectedSupplyAssets(marketParams, user) expect (uint256);

}

ghost ghostExpectedSupply(address, address, address, address, uint256, address) returns uint256;

function summaryExpectedSupplyAssets(MorphoHarness.MarketParams marketParams, address user) returns uint256 {
    return ghostExpectedSupply(marketParams.loanToken, marketParams.collateralToken, marketParams.oracle, marketParams.irm, marketParams.lltv, user);
}

rule skimDoesNotAffectAccounting(env e, address token) {

  require e.msg.sender == MorphoVaultV1Adapter.skimRecipient();
  uint256 realAssetsBefore = MorphoVaultV1Adapter.realAssets(e);

  //MorphoVaultV1Adapter.skim(e, token);

  uint256 realAssetsAfter = MorphoVaultV1Adapter.realAssets(e);
  assert realAssetsAfter == realAssetsBefore;
}
