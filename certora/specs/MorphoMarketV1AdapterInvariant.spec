// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using VaultV2 as VaultV2;
using MorphoMarketV1Adapter as MorphoMarketV1Adapter;

methods {
    function _.asset() external => DISPATCHER(true);
}

strong invariant assetMatch()
    VaultV2.asset == MorphoMarketV1Adapter.asset;
