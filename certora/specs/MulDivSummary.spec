// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/MulDiv.spec";

// Check Newton precision doubling from 4 to 8 bits with explicit error and wrap witnesses.
rule newton4(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 4) == 1, "The preceding iteration supplies the current inverse precision";
    uint256 next = newton(d, inv);
    mathint expression = inv * (2 - d * inv);
    assert (expression - next) % B() == 0;
    mathint wrap = (expression - next) / B();
    assert expression == next + wrap * B();
    mathint error = (d * inv - 1) / (2 ^ 4);
    assert d * inv == 1 + (2 ^ 4) * error;
    assert d * expression == 1 - (2 ^ 8) * error * error;
    assert (d * next) % (2 ^ 8) == 1;
}

// Check Newton precision doubling from 8 to 16 bits with explicit error and wrap witnesses.
rule newton8(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 8) == 1, "The preceding iteration supplies the current inverse precision";
    uint256 next = newton(d, inv);
    mathint expression = inv * (2 - d * inv);
    assert (expression - next) % B() == 0;
    mathint wrap = (expression - next) / B();
    assert expression == next + wrap * B();
    mathint error = (d * inv - 1) / (2 ^ 8);
    assert d * inv == 1 + (2 ^ 8) * error;
    assert d * expression == 1 - (2 ^ 16) * error * error;
    assert (d * next) % (2 ^ 16) == 1;
}

// Check Newton precision doubling from 16 to 32 bits with explicit error and wrap witnesses.
rule newton16(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 16) == 1, "The preceding iteration supplies the current inverse precision";
    uint256 next = newton(d, inv);
    mathint expression = inv * (2 - d * inv);
    assert (expression - next) % B() == 0;
    mathint wrap = (expression - next) / B();
    assert expression == next + wrap * B();
    mathint error = (d * inv - 1) / (2 ^ 16);
    assert d * inv == 1 + (2 ^ 16) * error;
    assert d * expression == 1 - (2 ^ 32) * error * error;
    assert (d * next) % (2 ^ 32) == 1;
}

// Check Newton precision doubling from 32 to 64 bits with explicit error and wrap witnesses.
rule newton32(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 32) == 1, "The preceding iteration supplies the current inverse precision";
    uint256 next = newton(d, inv);
    mathint expression = inv * (2 - d * inv);
    assert (expression - next) % B() == 0;
    mathint wrap = (expression - next) / B();
    assert expression == next + wrap * B();
    mathint error = (d * inv - 1) / (2 ^ 32);
    assert d * inv == 1 + (2 ^ 32) * error;
    assert d * expression == 1 - (2 ^ 64) * error * error;
    assert (d * next) % (2 ^ 64) == 1;
}

// Check Newton precision doubling from 64 to 128 bits with explicit error and wrap witnesses.
rule newton64(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 64) == 1, "The preceding iteration supplies the current inverse precision";
    uint256 next = newton(d, inv);
    mathint expression = inv * (2 - d * inv);
    assert (expression - next) % B() == 0;
    mathint wrap = (expression - next) / B();
    assert expression == next + wrap * B();
    mathint error = (d * inv - 1) / (2 ^ 64);
    assert d * inv == 1 + (2 ^ 64) * error;
    assert d * expression == 1 - (2 ^ 128) * error * error;
    assert (d * next) % (2 ^ 128) == 1;
}

// Check Newton precision doubling from 128 to 256 bits with explicit error and wrap witnesses.
rule newton128(uint256 d, uint256 inv) {
    require d % 2 == 1 && (d * inv) % (2 ^ 128) == 1, "The preceding iteration supplies the current inverse precision";
    uint256 next = newton(d, inv);
    mathint expression = inv * (2 - d * inv);
    assert (expression - next) % B() == 0;
    mathint wrap = (expression - next) / B();
    assert expression == next + wrap * B();
    mathint error = (d * inv - 1) / (2 ^ 128);
    assert d * inv == 1 + (2 ^ 128) * error;
    assert d * expression == 1 - (2 ^ 256) * error * error;
    assert (d * next) % (2 ^ 256) == 1;
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

// Check subtract_product: borrowing subtracts the remainder from the two-limb number exactly.
rule subtractProduct(uint256 hi, uint256 lo, uint256 r) {
    require r <= hi * B() + lo;
    uint256 newHi;
    uint256 newLo;
    newHi, newLo = subtract(hi, lo, r);
    assert newHi * B() + newLo == hi * B() + lo - r;
}

// Check the final unchecked multiplication returns the low word of the exact product.
rule finalProductCorrect(uint256 lo, uint256 inv) {
    uint256 result = finalProduct(lo, inv);
    assert result == (lo * inv) % B();
}
