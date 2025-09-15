// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function timelock(bytes4) external returns uint256 envfree;
    function executableAt(bytes) external returns uint256 envfree;
    function abdicated(bytes4) external returns bool envfree;

    function Utils.toBytes4(bytes) external returns bytes4 envfree;
}

rule abdicatedFunctionsCantBeCalled(env e, method f, calldataarg args) {
    require abdicated(to_bytes4(f.selector));
    
    f@withrevert(e, args);
    
    assert lastReverted;
}

invariant abdicatedCantBeDeabdicated(bytes4 selector)
    abdicated(selector);