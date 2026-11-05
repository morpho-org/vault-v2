// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/MulDiv.spec";

methods {
    function newton(uint256, uint256) external returns (uint256) envfree;
}

// Check one Newton precision doubling independently of the XOR seed and other iterations.
rule newtonLift(uint256 d, uint256 inv, uint256 m) {
    require m > 1 && m <= 2 ^ 128 && B() % (m * m) == 0, "The squared precision divides the word modulus";
    require (d * inv) % m == 1, "The previous iteration is an inverse at precision m";
    uint256 next = newton(d, inv);
    assert (d * next) % (m * m) == 1;
}

// Check the exact revert condition of the unsummarized OpenZeppelin implementation.
rule mulDivReverts(uint256 x, uint256 y, uint256 d) {
    mulDiv@withrevert(x, y, d);
    assert lastReverted <=> d == 0 || x * y / d >= B();
}

// Check the returned floor quotient of the unsummarized OpenZeppelin implementation.
rule mulDivValue(uint256 x, uint256 y, uint256 d) {
    uint256 result = mulDiv@withrevert(x, y, d);
    assert !lastReverted => d != 0 && result == x * y / d;
}

// Check that the split implementation has the same revert and return behavior without summaries.
rule stepsEquivalent(uint256 x, uint256 y, uint256 d) {
    uint256 actual = mulDiv@withrevert(x, y, d);
    bool actualReverted = lastReverted;
    uint256 split = mulDivSteps@withrevert(x, y, d);
    bool splitReverted = lastReverted;
    assert actualReverted == splitReverted;
    assert !actualReverted && !splitReverted => actual == split;
}

// Check high_product: the CRT block reconstructs both limbs of the exact product.
rule highProduct(uint256 x, uint256 y) {
    uint256 hi;
    uint256 lo;
    hi, lo = product(x, y);
    assert hi == x * y / B();
    assert lo == x * y % B();
}

// Check reverts_iff: the high-limb panic condition is exactly quotient overflow.
rule panicCondition(uint256 x, uint256 y, uint256 d) {
    require d > 0;
    uint256 hi;
    uint256 lo;
    hi, lo = product(x, y);
    assert d <= hi <=> x * y / d >= B();
}

// Check subtract_product: borrowing subtracts the remainder from the two-limb number exactly.
rule subtractProduct(uint256 hi, uint256 lo, uint256 r) {
    require r <= hi * B() + lo;
    uint256 newHi;
    uint256 newLo;
    newHi, newLo = subtract(hi, lo, r);
    assert newHi * B() + newLo == hi * B() + lo - r;
}

// Check twos and flip: the extracted divisor leaves an odd quotient and flips modulo B.
rule twosAndFlip(uint256 d) {
    require d > 0;
    uint256 odd;
    uint256 t;
    uint256 flipped;
    odd, t, flipped = twos(d);
    assert twosPost(d, odd, t, flipped);
}

// Check shift_combine: the disjoint OR reconstructs the low word after power-of-two division.
rule shiftCombine(uint256 hi, uint256 lo, uint256 t, uint256 flipped) {
    require shiftPre(t, flipped);
    uint256 result = shift(hi, lo, t, flipped);
    assert result == ((hi * B() + lo) / t) % B();
}

// Check inverse_correct: the seed and six Newton updates invert every odd denominator modulo B.
rule inverseCorrect(uint256 d) {
    require d % 2 == 1;
    uint256 inv = inverse(d);
    assert (d * inv) % B() == 1;
}

// Check the final unchecked multiplication returns the low word of the exact product.
rule finalProductCorrect(uint256 lo, uint256 inv) {
    uint256 result = finalProduct(lo, inv);
    assert result == (lo * inv) % B();
}
