// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

rule ownerCanChangeOwner(env e, address newOwner) {
    // Setup the caller to be the contract owner.
    require e.msg.sender == currentContract.owner;

    setOwner@withrevert(e, newOwner);
    assert lastReverted <=> e.msg.value != 0;
}

rule ownerCanChangeCurator(env e, address newCurator) {
    // Setup the caller to be the contract owner.
    require e.msg.sender == currentContract.owner;

    setCurator@withrevert(e, newCurator);
    assert lastReverted <=> e.msg.value != 0;

}

rule ownerCanUnsetSentinel(env e, address sentinel) {
    // Setup the caller to be the contract owner.
    require e.msg.sender == currentContract.owner;

    setIsSentinel@withrevert(e, sentinel, false);
    assert lastReverted <=> e.msg.value != 0;
}
