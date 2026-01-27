// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using MorphoHarness as MorphoMarketV1;

methods {

  function MorphoMarketV1AdapterV2.skimRecipient() external returns (address) envfree;

  // Assume that skim transfers do not revert.
  function SafeERC20Lib.safeTransfer(address, address, uint256) internal => NONDET;

  // assume adaptiveIRM rate is not changed by skim.
  function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => constantBorrowRate expect(uint256);

}

persistent ghost uint256 constantBorrowRate;

rule skimDoesNotAffectAccounting(env e, address token) {

  require e.msg.sender == MorphoMarketV1AdapterV2.skimRecipient();
  uint256 realAssetsBefore = MorphoMarketV1AdapterV2.realAssets(e);

  MorphoMarketV1AdapterV2.skim(e, token);

  uint256 realAssetsAfter = MorphoMarketV1AdapterV2.realAssets(e);
  assert realAssetsAfter == realAssetsBefore;
}
