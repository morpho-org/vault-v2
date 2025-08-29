// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function timelock(bytes4 selector) external returns uint256 envfree;

    function Utils.toBytes4(bytes) external returns bytes4 envfree;
}

// Check that abdicating a function set their timelock to infinity.
rule abdicatedFunctionHasInfiniteTimelock(env e, bytes4 selector) {
    abdicateSubmit(e, selector);

    assert timelock(selector) == max_uint256;
}

// Check that changes corresponding to functions that have been abdicated can't be submitted.
rule abdicatedFunctionsCantBeSubmitted(env e, bytes data) {
    // Safe require in a non trivial chain.
    require e.block.timestamp > 0;

    // Check that the function is not decreaseTimelock as its timelock is automatic.
    require(Utils.toBytes4(data) != to_bytes4(sig:VaultV2.decreaseTimelock(bytes4, uint256).selector));
    // Assume that the function has been abdicated.
    require timelock(Utils.toBytes4(data)) == max_uint256;

    submit@withrevert(e, data);
    assert lastReverted;
}

// Check that timelocks corresponding to functions that have been abdicated can't be decreased.
rule abdicatedFunctionsTimelocksCantBeDecreased(env e, bytes data, uint newDuration) {
    // Safe require in a non trivial chain.
    require e.block.timestamp > 0;

    // Noops are allowed
    require newDuration != type(uint256).max;

    // Check that the function is not decreaseTimelock as its timelock is automatic.
    require(Utils.toBytes4(data) != to_bytes4(sig:VaultV2.decreaseTimelock(bytes4, uint256).selector));
    // Assume that the function has been abdicated.
    require timelock(Utils.toBytes4(data)) == max_uint256;

    decreaseTimelock(Utils.toBytes4(data), newDuration)@withrevert(e, data);
    assert lastReverted;
}
