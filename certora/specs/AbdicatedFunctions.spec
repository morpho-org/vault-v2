// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => NONDET DELETE;
    function abdicated(bytes4) external returns bool envfree;
}

rule abdicatedFunctionsCantBeCalled(env e, method f, calldataarg args) {
    require abdicated(to_bytes4(f.selector));
    
    f@withrevert(e, args);
    
    assert lastReverted;
}

invariant abdicatedCantBeDeabdicated(bytes4 selector)
    abdicated(selector);