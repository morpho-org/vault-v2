// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

rule ownerCanChangeOwner(env e, address newOwner) {
    // Setup the caller to be the contract owner.
    require e.msg.sender == currentContract.owner;

    require e.msg.value == 0;

    setOwner@withrevert(e, newOwner);
    assert !lastReverted;
}

rule ownerCanChangeCurator(env e, address newCurator) {
    // Setup the caller to be the contract owner.
    require e.msg.sender == currentContract.owner;

    require e.msg.value == 0;

    setCurator@withrevert(e, newCurator);
    assert !lastReverted;

}

rule ownerCanUnsetSentinel(env e, address sentinel, bool newStatus) {
    // Setup the caller to be the contract owner.
    require e.msg.sender == currentContract.owner;

    require e.msg.value == 0;

    bool statusBefore = isSentinel(e, sentinel);

    setIsSentinel@withrevert(e, sentinel, newStatus);
    assert !lastReverted;
    satisfy statusBefore != isSentinel(e, sentinel);
}
