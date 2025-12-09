// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;
using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using MorphoHarness as MorphoMarketV1;

methods {
    function MorphoMarketV1AdapterV2.expectedSupplyAssets(bytes32) external returns (uint256) envfree;
    function MorphoHarness.totalSupplyShares(MorphoHarness.Id) external returns (uint256) envfree;
    function Utils.wrapId(bytes32) external returns (MorphoHarness.Id) envfree;

    function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => constantBorrowRate() expect(uint256);
    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate() expect(uint256);

    function _.position(MorphoHarness.Id, address) external => DISPATCHER(true);
    function _.market(MorphoHarness.Id) external => DISPATCHER(true);
}

ghost constantBorrowRate() returns uint256;

invariant expectedSupplyAssetsIsBounded(bytes32 marketId)
    MorphoMarketV1AdapterV2.expectedSupplyAssets(marketId) < 2 ^ 128
{ preserved {
    require MorphoMarketV1AdapterV2.supplyShares[marketId] <= MorphoMarketV1.totalSupplyShares(Utils.wrapId(marketId));
  }
}
