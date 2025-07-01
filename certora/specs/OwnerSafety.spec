// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

rule ownerCanChangeOwner(env e, address newOwner) {
    require (e.msg.sender == currentContract.owner, "setup the call to be performed by the owner of the contract");
    require (e.msg.value == 0, "setup the call to have no ETH value");;

    setOwner@withrevert(e, newOwner);
    assert !lastReverted;
}

rule ownerCanChangeCurator(env e, address newCurator) {
    require (e.msg.sender == currentContract.owner, "setup the call to be performed by the owner of the contract");
    require (e.msg.value == 0, "setup the call to have no ETH value");;

    setCurator@withrevert(e, newCurator);
    assert !lastReverted;

}

rule ownerCanUnsetSentinel(env e, address sentinel, bool newStatus) {
    require (e.msg.sender == currentContract.owner, "setup the call to be performed by the owner of the contract");
    require (e.msg.value == 0, "setup the call to have no ETH value");;

    bool statusBefore = isSentinel(e, sentinel);

    setIsSentinel@withrevert(e, sentinel, newStatus);
    assert !lastReverted;
    satisfy statusBefore != isSentinel(e, sentinel);
}
