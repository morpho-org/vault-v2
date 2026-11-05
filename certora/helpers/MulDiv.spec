// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

methods {
    function mulDiv(uint256, uint256, uint256) external returns (uint256) envfree;
    function mulDivSteps(uint256, uint256, uint256) external returns (uint256) envfree;
    function product(uint256, uint256) external returns (uint256, uint256) envfree;
    function subtract(uint256, uint256, uint256) external returns (uint256, uint256) envfree;
    function twos(uint256) external returns (uint256, uint256, uint256) envfree;
    function shift(uint256, uint256, uint256, uint256) external returns (uint256) envfree;
    function inverse(uint256) external returns (uint256) envfree;
    function finalProduct(uint256, uint256) external returns (uint256) envfree;
}

definition B() returns mathint = 2 ^ 256;

definition twosPost(uint256 d, uint256 odd, uint256 t, uint256 flipped) returns bool = t > 0 && t <= d && d % t == 0 && B() % t == 0 && odd == d / t && odd % 2 == 1 && flipped == (B() / t) % B();

definition shiftPre(uint256 t, uint256 flipped) returns bool = t > 0 && B() % t == 0 && flipped == (B() / t) % B();
