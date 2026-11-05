// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/MulDiv.spec";

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
