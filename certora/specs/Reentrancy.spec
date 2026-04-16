// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using MorphoVaultV1Adapter as MorphoVaultV1Adapter;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isAdapter(address) external returns bool envfree;

    function _.accrueInterest(MorphoMarketV1AdapterV2.MarketParams) external => ignoredCallVoidSummary() expect void;

    // Assume that adapters are either MorphoMarketV1AdapterV2 or MorphoVaultV1Adapter.
    function _.allocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);
    function _.deallocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);

    function _.supply(MorphoMarketV1AdapterV2.MarketParams, uint256, uint256, address, bytes) external => ignoredCallUintPairSummary() expect (uint256, uint256);
    function _.withdraw(MorphoMarketV1AdapterV2.MarketParams, uint256, uint256, address, address) external => ignoredCallUintPairSummary() expect (uint256, uint256);
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

hook CALL(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    // Ignore calls to tokens and Morpho markets and Metamorpho as they are trusted to not reenter (they have gone through a timelock).
    if (ignoredCall || addr == currentContract) {
        ignoredCall = false;
    } else if (addr == MorphoMarketV1AdapterV2 || addr == MorphoVaultV1Adapter) {
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
