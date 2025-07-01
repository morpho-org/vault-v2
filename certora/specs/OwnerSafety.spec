// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function owner() external returns address envfree;
    function curator() external returns address envfree;
    function isSentinel(address) external returns bool envfree;
}

rule ownerCanChangeOwner(env e, address newOwner) {
    require (e.msg.sender == currentContract.owner, "setup the call to be performed by the owner of the contract");
    require (e.msg.value == 0, "setup the call to have no ETH value");

    setOwner@withrevert(e, newOwner);
    assert !lastReverted;
    assert owner() == newOwner;
}

rule ownerCanChangeCurator(env e, address newCurator) {
    require (e.msg.sender == currentContract.owner, "setup the call to be performed by the owner of the contract");
    require (e.msg.value == 0, "setup the call to have no ETH value");

    setCurator@withrevert(e, newCurator);
    assert !lastReverted;
    assert curator() == newCurator;
}

rule ownerCanSetSentinel(env e, address sentinel, bool newStatus) {
    require (e.msg.sender == currentContract.owner, "setup the call to be performed by the owner of the contract");
    require (e.msg.value == 0, "setup the call to have no ETH value");

    setIsSentinel@withrevert(e, sentinel, newStatus);
    assert !lastReverted;
    assert isSentinel(sentinel) == newStatus;
}
