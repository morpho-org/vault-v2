// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function Utils.libMulDivUp(uint256, uint256, uint256) external returns (uint256) envfree;
}

rule mulDivUpIsAtLeastExactQuotient(uint256 x, uint256 y, uint256 d) {
    uint256 result = Utils.libMulDivUp(x, y, d);

    assert result * d >= x * y;
}

rule mulDivUpIsLessThanExactQuotientPlusOne(uint256 x, uint256 y, uint256 d) {
    uint256 result = Utils.libMulDivUp(x, y, d);

    assert (result - 1) * d < x * y;
}
