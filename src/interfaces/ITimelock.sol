// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.8.0;

enum Operation {
    Submit,
    Revoke,
    IncreaseTimelock,
    DecreaseTimelock,
    Abdicate
}

struct Config {
    uint256 delay;
    bool abdicated;
}

struct TimelockStatus {
    uint256 delay;
    bool abdicated;
    uint256 executableAt;
}

bytes4 constant TIMELOCK_OPERATION_SELECTOR = bytes4(keccak256("timelockOperation(uint8,bytes32,bytes)"));

bytes32 constant DECREASE_TIMELOCK_KEY = bytes32(uint256(Operation.DecreaseTimelock) + 1);

interface ITimelock {
    event Submit(address indexed account, bytes32 indexed key, bytes data, uint256 executableAt);
    event Revoke(address indexed account, bytes32 indexed key, bytes data);
    event Accept(address indexed account, bytes32 indexed key, bytes data);
    event Abdicate(address indexed account, bytes32 indexed key);
    event IncreaseTimelock(address indexed account, bytes32 indexed key, uint256 newDuration);
    event DecreaseTimelock(address indexed account, bytes32 indexed key, uint256 newDuration);

    error Abdicated();
    error AutomaticallyTimelocked();
    error DataAlreadyPending();
    error DataNotTimelocked();
    error Invalid();
    error TimelockNotDecreasing();
    error TimelockNotIncreasing();

    function operation(Operation op, bytes32 key, bytes calldata data) external;
    function useTimelock(bytes calldata data) external;
    function status(address account, bytes calldata data) external view returns (TimelockStatus memory);
    function getKey(bytes calldata data) external pure returns (bytes32);
}
