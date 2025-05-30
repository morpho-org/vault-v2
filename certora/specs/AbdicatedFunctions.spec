// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function timelock(bytes4 selector) external returns uint256 envfree;

    function Utils.toBytes4(bytes) external returns bytes4 envfree;
}

rule abidcatedFunctionHasInfiniteTimelock(env e, bytes4 selector) {
    abdicateSubmit(e, selector);

    assert timelock(selector) == 2^256 - 1;
}

rule inifiniteTimelockCantBeChanged(env e, method f, calldataarg data, bytes4 selector) {
    require timelock(selector) == 2^256 - 1;

    f(e, data);

    assert timelock(selector) == 2^256 - 1;
}

rule abdicatedFunctionsCantBeSubmitted(env e, bytes4 selector, bytes data) {
    // Safe require in a non trivial chain.
    require e.block.timestamp > 0;

    // Assume that the function has been abdicated.
    require timelock(selector) == 2^256 - 1;
    // Check that submitting this function selector specifically.
    require Utils.toBytes4(data) == selector;

    submit@withrevert(e, data);
    assert lastReverted;
}
