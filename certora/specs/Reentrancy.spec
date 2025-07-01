// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoVaultV1Adapter as MorphoVaultV1Adapter;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function _.allocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);
    function _.deallocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);
    function _.realizeLoss(bytes, bytes4, address) external => DISPATCHER(true);

    function _.supply(MorphoMarketV1Adapter.MarketParams, uint256, uint256, address, bytes) external => uintPairSummary() expect (uint256, uint256);
    function _.withdraw(MorphoMarketV1Adapter.MarketParams, uint256, uint256, address, address) external => uintPairSummary() expect (uint256, uint256);
    function _.deposit(uint256, address) external => uintSummary() expect uint256 ;
    function _.withdraw(uint256, address, address) external => uintSummary() expect uint256;


    function _.transfer(address, uint256) external => boolSummary() expect bool;
    function _.transferFrom(address, address, uint256) external => boolSummary() expect bool;
    function _.balanceOf(address) external => uintSummary() expect uint256;
}

function boolSummary() returns bool {
    ignoredCall = true;
    bool value;
    return value;
}

function uintPairSummary() returns (uint256, uint256) {
    ignoredCall = true;
    uint256[2] values;
    return (values[0], values[1]);
}

function uintSummary() returns uint256 {
    ignoredCall = true;
    uint256 value;
    return value;
}

persistent ghost bool ignoredCall;
persistent ghost bool hasCall;

hook CALL(uint g, address addr, uint value, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    if (ignoredCall || addr == MorphoMarketV1Adapter || addr == MorphoVaultV1Adapter || addr == currentContract) {
        // Ignore calls to tokens and Morpho markets and Metamorpho as they are trusted to not reenter (they have gone through a timelock).
        ignoredCall = false;
    } else {
        hasCall = true;
    }
}

// Check that there are no untrusted external calls, ensuring notably reentrancy safety.
rule reentrancySafe(method f, env e, calldataarg data) {
    require (!ignoredCall && !hasCall, "set up the initial ghost state");
    f(e,data);
    assert !hasCall;
}
