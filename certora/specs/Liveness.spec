// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";


rule livenessSetVicIfDataIsTimelocked(env e, address newVic) {
    require e.msg.value == 0;

    setVicMocked@withrevert(e, newVic);
    assert !lastReverted;
}

rule livenessDecreaseAbsoluteCapZero(env e, bytes idData) {
    require e.msg.sender == curator() || isSentinel(e.msg.sender);
    require e.msg.value == 0;
    decreaseAbsoluteCap@withrevert(e, idData, 0);
    assert !lastReverted;
}

rule livenessDecreaseRelativeCapZero(env e, bytes idData) {
    require e.msg.sender == curator() || isSentinel(e.msg.sender);
    require e.msg.value == 0;
    decreaseRelativeCap@withrevert(e, idData, 0);
    assert !lastReverted;
}

rule livenessSetOwner(env e, address owner) {
    require e.msg.sender == owner();
    require e.msg.value == 0;
    setOwner@withrevert(e, owner);
    assert !lastReverted;
}

rule livenessSetCurator(env e, address curator) {
    require e.msg.sender == owner();
    require e.msg.value == 0;
    setCurator@withrevert(e, curator);
    assert !lastReverted;
}

rule livenessSetIsSentinel(env e, address account, bool isSentinel) {
    require e.msg.sender == owner();
    require e.msg.value == 0;
    setIsSentinel@withrevert(e, account, isSentinel);
    assert !lastReverted;
}

// Check authorized addresses can deallocate if forceDeallocate is possible.
rule livenessDeallocate(env e, env f, address adapter, bytes data, uint256 assets, address onBehalf) {

    // Safe require statements to instantiate two environments that differ only by the message sender.
    require e.msg.value == f.msg.value;
    require e.block.number == f.block.number;
    require e.block.timestamp == f.block.timestamp;
    require e.block.basefee == f.block.basefee;
    require e.block.coinbase == f.block.coinbase;
    require e.block.difficulty == f.block.difficulty;
    require e.block.gaslimit == f.block.gaslimit;
    require e.tx.origin == f.tx.origin;

    forceDeallocate@withrevert(e, adapter, data, assets, onBehalf);
    bool forceDeallocateReverted = lastReverted;

    // Safe require that ensure that f's message sender is allowed to dealocate.
    require isAllocator(f.msg.sender) || isSentinel(f.msg.sender) || f.msg.sender == currentContract;

    deallocate@withrevert(f, adapter, data, assets);
    assert !forceDeallocateReverted => !lastReverted;
}
