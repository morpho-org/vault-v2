// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using MorphoVaultV1Adapter as MorphoVaultV1Adapter;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function isAdapter(address) external returns bool envfree;

    function _.accrueInterest(MorphoMarketV1Adapter.MarketParams) external => ignoredCallVoidSummary() expect void;

    function _.allocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);
    function _.deallocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);

    function _.supply(MorphoMarketV1Adapter.MarketParams, uint256, uint256, address, bytes) external => ignoredCallUintPairSummary() expect (uint256, uint256);
    function _.withdraw(MorphoMarketV1Adapter.MarketParams, uint256, uint256, address, address) external => ignoredCallUintPairSummary() expect (uint256, uint256);
    function _.deposit(uint256, address) external => ignoredCallUintSummary() expect uint256 ;
    function _.withdraw(uint256, address, address) external => ignoredCallUintSummary() expect uint256;

    function _.transfer(address, uint256) external => ignoredCallBoolSummary() expect bool;
    function _.transferFrom(address, address, uint256) external => ignoredCallBoolSummary() expect bool;
    function _.balanceOf(address) external => ignoredCallUintSummary() expect uint256;
}

function ignoredCallVoidSummary() {
    ignoredCall = true;
}

function ignoredCallBoolSummary() returns bool {
    ignoredCall = true;
    bool value;
    return value;
}

function ignoredCallUintPairSummary() returns (uint256, uint256) {
    ignoredCall = true;
    uint256[2] values;
    return (values[0], values[1]);
}

function ignoredCallUintSummary() returns uint256 {
    ignoredCall = true;
    uint256 value;
    return value;
}

persistent ghost bool ignoredCall;
persistent ghost bool hasCall;

hook CALL(uint g, address addr, uint value, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc {
    // Ignore calls to tokens and Morpho markets and Metamorpho as they are trusted to not reenter (they have gone through a timelock).
    if (ignoredCall || addr == currentContract) {
        ignoredCall = false;
    } else if (addr == MorphoMarketV1Adapter || addr == MorphoVaultV1Adapter) {
        assert isAdapter(addr);
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
