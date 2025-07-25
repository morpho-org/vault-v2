// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function ERC20Mock.balanceOf(address) external returns (uint) envfree;
    function ERC20Mock.allowance(address,address) external returns (uint) envfree;
}
