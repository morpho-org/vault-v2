// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function MetaMorphoV1_1.balanceOf(address) external returns (uint) envfree;
    function MetaMorphoV1_1.withdrawQueueLength() external returns (uint) envfree;
    function MetaMorphoV1_1.supplyQueueLength() external returns (uint) envfree;
    function MetaMorphoV1_1._accruedFeeAndAssets() internal returns (uint, uint, uint) => CONSTANT;// Summarize this so we limit the complexity and don't need to go in Morpho
    function MetaMorphoV1_1._accrueInterest() internal => CONSTANT;// Summarize this so we limit the complexity and don't need to go in Morpho
}
