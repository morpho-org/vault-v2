// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using VaultV2 as VaultV2;
using MetaMorpho as MetaMorpho;

methods{
    function VaultV2.asset() external returns address envfree;
    function MetaMorpho.asset() external returns address envfree;
}

invariant assetMatch()
    VaultV2.asset() == MetaMorpho.asset();
