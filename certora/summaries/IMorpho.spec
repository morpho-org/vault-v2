// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    // We need borrowRate and borrowRateView to return the same value
    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);// We don't know which IRM will be used, just assume 3% borrow rate for simplicity
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => ALWAYS(95129375);// We don't know which IRM will be used, just assume 3% borrow rate for simplicity
    function _.onMorphoSupply(uint, bytes) external => NONDET DELETE;
}
