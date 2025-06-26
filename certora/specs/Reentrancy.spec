// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => NONDET DELETE;
    function accrueInterest() external => voidSummary();

    function _.allocate(bytes, uint256, bytes4, address) external => allocatorSummary() expect (bytes32[], uint256);
    function _.deallocate(bytes, uint256, bytes4, address) external => allocatorSummary() expect (bytes32[], uint256);
    function _.realizeLoss(bytes, bytes4, address) external => allocatorSummary() expect (bytes32[], uint256);

    function _.transfer(address, uint256) external => boolSummary() expect bool;
    function _.transferFrom(address, address, uint256) external => boolSummary() expect bool;
    function _.balanceOf(address) external => uintSummary() expect uint256;
}

function voidSummary() {
    ignoredCall = true;
}

function boolSummary() returns bool {
    ignoredCall = true;
    bool value;
    return value;
}

function uintSummary() returns uint256 {
    ignoredCall = true;
    uint256 value;
    return value;
}

function allocatorSummary() returns (bytes32[], uint256) {
    ignoredCall = true;
    bytes32[] ids;
    uint256 interests;
    return (ids, interests);
}

persistent ghost bool ignoredCall;
persistent ghost bool hasCall;

hook CALL(uint g, address addr, uint value, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    if (ignoredCall) {
        // Ignore calls to tokens and Morpho markets as they are trusted (they have gone through a timelock).
        ignoredCall = false;
    } else {
        hasCall = true;
    }
}

// Check that there are no untrusted external calls, ensuring notably reentrancy safety.
rule reentrancySafe(method f, env e, calldataarg data) {
    // Set up the initial state.
    require !ignoredCall && !hasCall;
    f(e,data);
    assert !hasCall;
}
