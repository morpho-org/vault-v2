// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/MulDiv.spec";

// Check extraction and flip with word-sized predicates and exact bitwise operations.
rule twosWord(uint256 d) {
    require d > 0, "The slow path has a positive denominator";
    uint256 odd;
    uint256 t;
    uint256 flipped;
    odd, t, flipped = twos(d);
    assert wordTwosPost(d, odd, t, flipped);
}

// Check that all six Newton updates produce a word inverse for every odd denominator.
rule inverseWord(uint256 d) {
    require d % 2 == 1, "The inverse is used only for odd denominators";
    uint256 inv = inverse(d);
    uint256 residue = finalProduct(d, inv);
    assert residue == 1;
}

// Check that the OR combines disjoint limbs into their sum.
rule shiftWord(uint256 hi, uint256 lo, uint256 t, uint256 flipped) {
    require wordShiftPre(t, flipped), "The divisor divides the word modulus and the flip is exact";
    uint256 high = finalProduct(hi, flipped);
    uint256 result = shift(hi, lo, t, flipped);
    assert result == lo / t + high;
}
