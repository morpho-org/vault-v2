// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

methods {
    function isAllocator(address) external returns bool envfree;
    function firstTotalAssets() external returns uint256 envfree;
    function _.allocate(bytes, uint256) external => CONSTANT;
    function _.safeTransfer(address, address, uint256) internal => CONSTANT;
}

ghost mapping(bytes32 => uint128) ghostAbsoluteCap {
    init_state axiom forall bytes32 id. ghostAbsoluteCap[id] == 0;
}

ghost mapping(bytes32 => uint128) ghostRelativeCap {
    init_state axiom forall bytes32 id. ghostRelativeCap[id] == 0;
}

ghost mapping(bytes32 => uint256) ghostAllocation {
    init_state axiom forall bytes32 id. ghostAllocation[id] == 0;
}

hook Sload uint128 cap caps[KEY bytes32 id].absoluteCap {
    require ghostAbsoluteCap[id] == cap;
}

hook Sload uint128 cap caps[KEY bytes32 id].relativeCap {
    require ghostRelativeCap[id] == cap;
}

hook Sload uint256 alloc caps[KEY bytes32 id].allocation {
    require ghostAllocation[id] == alloc;
}

hook Sstore caps[KEY bytes32 id].absoluteCap uint128 newCap (uint128 _) {
    ghostAbsoluteCap[id] = newCap;
}

hook Sstore caps[KEY bytes32 id].relativeCap uint128 newCap (uint128 _) {
    ghostRelativeCap[id] = newCap;
}

hook Sstore caps[KEY bytes32 id].allocation uint256 newAllocation (uint256 _) {
    ghostAllocation[id] = newAllocation;
}

rule allocateReverts(env e, address adapter, bytes data, uint256 assets){
    // Assume no interest is accrued.
    require currentContract.lastUpdate == e.block.timestamp;

    require currentContract.asset != 0x00;

    bool unauthorizedCaller =
        !isAllocator(e.msg.sender)
        || e.msg.sender != currentContract
        || !isAdapter(adapter);
    uint128 wad = assert_uint128(Utils.wad());
    uint256 firstTotalAssetsB = firstTotalAssets();
    allocate@withrevert(e, adapter, data, assets);

    assert
        lastReverted =>
        unauthorizedCaller
        || e.msg.value != 0
        || (exists bytes32 id .
            ghostAbsoluteCap[id] == 0
            || ghostAllocation[id] > ghostAbsoluteCap[id]
            || ghostRelativeCap[id] != wad
            || ghostAllocation[id] > (firstTotalAssetsB * ghostAllocation[id]) / wad);
}
