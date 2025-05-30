// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function owner() external returns (address) envfree;
    function executableAt(bytes) external returns (uint256) envfree;

    function Utils.encodeSetIsAllocatorCall(uint32, address, bool) external returns (bytes) envfree;
}

function dataNotExecutableAt(bytes data, uint256 timestamp) returns bool {
    uint256 executableAt = executableAt(data);
    return executableAt == 0 || executableAt > timestamp;
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

// Check the revert condition for the setIsAllocator function.
rule setIsAllocatorRevertCondition(env e, address account, bool newIsAllocator) {
    bytes data = Utils.encodeSetIsAllocatorCall(sig:setIsAllocator(address, bool).selector, account, newIsAllocator);
    bool notExecutable = dataNotExecutableAt(data, e.block.timestamp);
    setIsAllocator@withrevert(e, account, newIsAllocator);
    assert lastReverted <=> e.msg.value != 0 || notExecutable;
}
