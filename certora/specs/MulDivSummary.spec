// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/MulDiv.spec";

methods {
    function newton(uint256, uint256) external returns (uint256) envfree;
}

// Check the polynomial identity underlying Newton error squaring with an explicit error witness.
rule newtonIdentity(mathint a, mathint p, mathint m) {
    require a == 1 + p * m, "The error is an explicit multiple of the current precision";
    assert a * (2 - a) == 1 - p * p * m * m;
}

// Check that the unchecked Newton block differs from its integer expression by a whole word.
rule newtonWord(uint256 d, uint256 inv) {
    uint256 next = newton(d, inv);
    mathint expression = inv * (2 - d * inv);
    assert (expression - next) % B() == 0;
}

// Check quotient bounds from a product's high limb independently of the implementation.
rule quotientBound(uint256 x, uint256 y, uint256 d, uint256 hi) {
    require hi == x * y / B() && hi < d, "The high product limb lies below the denominator";
    mathint q = x * y / d;
    assert d > 0 && q >= 0 && q < B();
}

// Check exact cancellation of the extracted factor with an explicit quotient witness.
rule divideFactor(uint256 hi, uint256 lo, uint256 d, uint256 t, uint256 q, uint256 odd) {
    require t > 0 && d == t * odd, "The divisor has an explicit factorization";
    require hi * B() + lo == d * q, "Remainder subtraction leaves the exact divisor times quotient";
    assert (hi * B() + lo) / t == odd * q;
}

// Check modular inverse cancellation using explicit witnesses for the two modular reductions.
rule inverseCancel(uint256 d, uint256 q, uint256 inv, uint256 lo, mathint a, mathint b) {
    require d * q == a * B() + lo, "The low word is the remainder of divisor times quotient";
    require d * inv == b * B() + 1, "The inverse product has remainder one";
    assert (lo * inv) % B() == q;
}

// Check that the word-only twos postcondition implies the integer postcondition.
rule twosBridge(uint256 d, uint256 odd, uint256 t, uint256 flipped) {
    require t > 0 && t <= d && d % t == 0 && odd == d / t && odd % 2 == 1, "The word lemma establishes exact division and an odd quotient";
    require max_uint256 % t == t - 1 && flipped == (t == 1 ? 0 : max_uint256 / t + 1), "The word lemma establishes the max-word residue and flip";
    assert twosPost(d, odd, t, flipped);
}

// Check arithmetic reconstruction after the bitwise OR has been replaced by a disjoint sum.
rule shiftArithmetic(uint256 hi, uint256 lo, uint256 t, uint256 flipped) {
    require shiftPre(t, flipped), "The divisor divides the word modulus and the flip is exact";
    mathint low = lo / t;
    mathint high = (hi * flipped) % B();
    assert low < B() / t;
    assert t == 1 || high % (B() / t) == 0;
    assert (low + high) % B() == ((hi * B() + lo) / t) % B();
}

// Check one Newton precision doubling independently of the XOR seed and other iterations.
// Check Newton precision doubling from 4 to 8 bits with a constant modulus.
rule newton4(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 4) == 1, "The preceding iteration supplies an odd-denominator inverse";
    uint256 next = newton(d, inv);
    assert (d * next) % (2 ^ 8) == 1;
}

// Check Newton precision doubling from 8 to 16 bits with a constant modulus.
rule newton8(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 8) == 1, "The preceding iteration supplies an odd-denominator inverse";
    uint256 next = newton(d, inv);
    assert (d * next) % (2 ^ 16) == 1;
}

// Check Newton precision doubling from 16 to 32 bits with a constant modulus.
rule newton16(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 16) == 1, "The preceding iteration supplies an odd-denominator inverse";
    uint256 next = newton(d, inv);
    assert (d * next) % (2 ^ 32) == 1;
}

// Check Newton precision doubling from 32 to 64 bits with a constant modulus.
rule newton32(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 32) == 1, "The preceding iteration supplies an odd-denominator inverse";
    uint256 next = newton(d, inv);
    assert (d * next) % (2 ^ 64) == 1;
}

// Check Newton precision doubling from 64 to 128 bits with a constant modulus.
rule newton64(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 64) == 1, "The preceding iteration supplies an odd-denominator inverse";
    uint256 next = newton(d, inv);
    assert (d * next) % (2 ^ 128) == 1;
}

// Check Newton precision doubling from 128 to 256 bits with a constant modulus.
rule newton128(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 128) == 1, "The preceding iteration supplies an odd-denominator inverse";
    uint256 next = newton(d, inv);
    assert (d * next) % (2 ^ 256) == 1;
}

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
