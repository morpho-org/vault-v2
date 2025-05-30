// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function owner() external returns (address) envfree;
}

// Check the revert condition for the setOwner function.
rule setOwnerRevertCondition(env e, address newOwner) {
    address oldOwner = owner();
    setOwner@withrevert(e, newOwner);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner;
}

// Check the revert condition for the setCurator function.
rule setCuratorRevertCondition(env e, address newCurator) {
    address oldOwner = owner();
    setCurator@withrevert(e, newCurator);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner;
}

// Check the revert condition for the setIsSentinel function.
rule setIsSentinelRevertCondition(env e, address account, bool newIsSentinel) {
    address oldOwner = owner();
    setIsSentinel@withrevert(e, account, newIsSentinel);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner;
}
