// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

methods {
    function bitAnd(uint256, uint256) external returns (uint256) envfree;
    function bitOr(uint256, uint256) external returns (uint256) envfree;
    function seedResidue(uint256) external returns (uint256) envfree;
    function inverseResidue(uint256) external returns (uint256) envfree;
    function twosWordPost(uint256) external returns (bool) envfree;
    function shiftWordPost(uint256, uint256, uint256, uint256) external returns (bool) envfree;
}

// Check that OR on disjoint words is their wrapped sum.
rule disjointOr(uint256 a, uint256 b) {
    require bitAnd(a, b) == 0, "The lemma is restricted to disjoint bit supports";
    assert bitOr(a, b) == to_uint256(a + b);
}

// Check that a power-of-two-aligned high word does not overlap a bounded low word.
rule alignedDisjoint(uint256 a, uint256 b, uint256 k) {
    require k > 0 && k < 256, "The alignment is a nontrivial word-sized power of two";
    uint256 alignment = 1 << k;
    require a < alignment && b % alignment == 0, "Low bits and high bits occupy separate ranges";
    assert bitAnd(a, b) == 0;
}

// Check the XOR seed modulo 16 with exact bitwise operations and word-sized values only.
rule seedWord(uint256 d) {
    require d % 2 == 1, "The inverse seed is used only for odd denominators";
    assert seedResidue(d) == 1;
}

// Check the six Newton updates using wrapped multiplication rather than a 257-bit modulus.
rule inverseWord(uint256 d) {
    require d % 2 == 1, "The inverse is used only for odd denominators";
    assert inverseResidue(d) == 1;
}

// Check extraction and flip using max-word residues instead of the out-of-range constant 2^256.
rule twosWord(uint256 d) {
    require d > 0, "The slow path has a positive denominator";
    assert twosWordPost(d);
}

// Check that the OR combines disjoint limbs into their wrapped sum.
rule shiftWord(uint256 hi, uint256 lo, uint256 t, uint256 flipped) {
    require t > 0, "Division uses the nonzero extracted power of two";
    require max_uint256 % t == t - 1, "The extracted divisor divides 2^256";
    require flipped == (t == 1 ? 0 : max_uint256 / t + 1), "The flip represents 2^256/t modulo 2^256";
    assert shiftWordPost(hi, lo, t, flipped);
}
