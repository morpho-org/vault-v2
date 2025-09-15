// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;
    
    function executableAt(bytes) external returns uint256 envfree;
}

// Cannot go from a>0 to b>0.
rule executableAtChange(env e, method f, calldataarg args, bytes data) {
    uint256 executableAtBefore = executableAt(data);

    f(e, args);

    uint256 executableAtAfter = executableAt(data);
    
    assert executableAtAfter == executableAtBefore
        || (executableAtAfter == 0 && executableAtBefore > 0)
        || (executableAtAfter > 0 && executableAtBefore == 0);
}
