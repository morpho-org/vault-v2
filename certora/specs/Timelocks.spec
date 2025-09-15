// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;
    
    function timelock(bytes4) external returns uint256 envfree;
    function executableAt(bytes) external returns uint256 envfree;

    function Utils.toBytes4(bytes) external returns bytes4 envfree;
}

rule executableAtUnzero(env e, method f, calldataarg args, bytes data) {
    bytes4 selector = Utils.toBytes4(data);
    require executableAt(data) == 0;

    f(e, args);

    assert executableAt(data) > 0 => executableAt(data) == e.block.timestamp + timelock(selector);
}

rule executableAtChange(env e, method f, calldataarg args, bytes data) {
    uint256 executableAtBefore = executableAt(data);

    f(e, args);

    uint256 executableAtAfter = executableAt(data);
    assert executableAtAfter == executableAtBefore || executableAtAfter == 0 || executableAtAfter == 0;
}
