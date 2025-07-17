// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

methods {
    function _.deallocate(bytes, uint256, bytes4, address) external
        => constantDeallocateSummary() expect (bytes32[], uint256);
}

persistent ghost mapping(uint256 => bytes32) idByIndex;
persistent ghost uint idsLength;
persistent ghost uint256 interest;

function constantGhostIds() returns bytes32[] {
    bytes32[] ids;
    require ids.lenght == idsLength;
    require forall uint i. i < ids.length => ids[i] == idByIndex[i];
    return ids;
}

function constantDeallocateSummary() returns (bytes32[], uint256) {
    bytes32[] ids = constantGhostIds();
    require (forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "assume that all returned ids are unique");

    return (ids, interest);
}

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

// Check that authorized addresses can deallocate if forceDeallocate is possible.
rule livenessDeallocate(env e, env f, address adapter, bytes data, uint256 assets, address onBehalf) {
    // Instantiate two environments that differ only by the message sender.
    require (e.msg.value == f.msg.value, "ack");
    require (e.block.number == f.block.number, "ack");
    require (e.block.timestamp == f.block.timestamp, "ack");
    require (e.block.basefee == f.block.basefee, "ack");
    require (e.block.coinbase == f.block.coinbase, "ack");
    require (e.block.difficulty == f.block.difficulty, "ack");
    require (e.block.gaslimit == f.block.gaslimit, "ack");
    require (e.tx.origin == f.tx.origin, "ack");

    storage s = lastStorage;

    forceDeallocate@withrevert(e, adapter, data, assets, onBehalf) at s;
    bool forceDeallocateDidntRevert = !lastReverted;

    require (isAllocator(f.msg.sender) || isSentinel(f.msg.sender), "assume the sender is authorized to deallocate");
    deallocate@withrevert(f, adapter, data, assets) at s;
    bool deallocateDidntRevert = !lastReverted;

    assert  forceDeallocateDidntRevert => deallocateDidntRevert;
}
