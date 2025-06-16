// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function timelock(bytes4 selector) external returns uint256 envfree;

    function Utils.toBytes4(bytes) external returns bytes4 envfree;
}

// Check that abdicating a function set their timelock to infinity.
rule abidcatedFunctionHasInfiniteTimelock(env e, bytes4 selector) {
    abdicateSubmit(e, selector);

    assert timelock(selector) == 2^256 - 1;
}

// Check that infinite timelocks can't be changed.
rule inifiniteTimelockCantBeChanged(env e, method f, calldataarg data, bytes4 selector) {
    require timelock(selector) == 2^256 - 1;

    f(e, data);

    assert timelock(selector) == 2^256 - 1;
}

// Check that changes corresponding to functions that have been abdicated can't be submitted.
rule abdicatedFunctionsCantBeSubmitted(env e, bytes data) {
    // Safe require in a non trivial chain.
    require e.block.timestamp > 0;

    // Assume that the function has been abdicated.
    require timelock(Utils.toBytes4(data)) == 2^256 - 1;

    submit@withrevert(e, data);
    assert lastReverted;
}
