// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "Invariants.spec";

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
