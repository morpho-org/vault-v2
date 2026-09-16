// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    ITimelock,
    Operation,
    Config,
    TimelockStatus,
    TIMELOCK_OPERATION_SELECTOR,
    DECREASE_TIMELOCK_KEY
} from "./interfaces/ITimelock.sol";

/// @dev Contracts authorize Submit/Revoke locally and call useTimelock before configuration operations.
/// @dev A key identifies an operation. It is either a right-padded arbitrary selector or a left-padded member of the
/// Operation enum.
/// @dev All writes are scoped to msg.sender.
contract Timelock is ITimelock {
    mapping(address account => mapping(bytes32 key => Config)) internal configs;
    mapping(address account => mapping(bytes data => uint256)) internal executableAt;

    function operation(Operation op, bytes calldata data) external {
        if (op == Operation.Submit) {
            require(executableAt[msg.sender][data] == 0, DataAlreadyPending());
            bytes32 key = getKey(data);
            Config storage config = configs[msg.sender][key];
            if (key == DECREASE_TIMELOCK_KEY) {
                (, bytes memory parameters) = abi.decode(data[4:], (Operation, bytes));
                config = configs[msg.sender][abi.decode(parameters, (bytes32))];
            }
            uint256 timestamp = block.timestamp + config.delay;
            executableAt[msg.sender][data] = timestamp;
            emit Submit(msg.sender, key, data, timestamp);
        } else if (op == Operation.Revoke) {
            require(executableAt[msg.sender][data] != 0, DataNotTimelocked());
            delete executableAt[msg.sender][data];
            emit Revoke(msg.sender, getKey(data), data);
        } else if (op == Operation.Abdicate) {
            bytes32 key = abi.decode(data, (bytes32));
            Config storage config = configs[msg.sender][key];
            config.abdicated = true;
            emit Abdicate(msg.sender, key);
        } else {
            (bytes32 key, uint256 newDuration) = abi.decode(data, (bytes32, uint256));
            require(key != DECREASE_TIMELOCK_KEY, AutomaticallyTimelocked());
            Config storage config = configs[msg.sender][key];
            if (op == Operation.IncreaseTimelock) {
                require(newDuration >= config.delay, TimelockNotIncreasing());
                emit IncreaseTimelock(msg.sender, key, newDuration);
            } else {
                require(newDuration <= config.delay, TimelockNotDecreasing());
                emit DecreaseTimelock(msg.sender, key, newDuration);
            }
            config.delay = newDuration;
        }
    }

    function useTimelock(bytes calldata data) public {
        require(block.timestamp - executableAt[msg.sender][data] != block.timestamp, Invalid());
        bytes32 key = getKey(data);
        require(!configs[msg.sender][key].abdicated, Abdicated());
        delete executableAt[msg.sender][data];
        emit Accept(msg.sender, key, data);
    }

    function status(address account, bytes calldata data) external view returns (TimelockStatus memory) {
        Config memory config = configs[account][getKey(data)];
        return TimelockStatus(config.delay, config.abdicated, executableAt[account][data]);
    }

    /// @dev Ordinary selectors are right-padded; op + 1 occupies the low byte, so their keys cannot collide.
    function getKey(bytes calldata data) public pure returns (bytes32) {
        // forge-lint: disable-next-line(unsafe-typecast) we explicitly want only the first bytes4.
        if (bytes4(data) == TIMELOCK_OPERATION_SELECTOR) {
            return bytes32(uint256(abi.decode(data[4:], (Operation))) + 1);
        }
        // forge-lint: disable-next-line(unsafe-typecast) we right-pad the first bytes4 to form the key.
        return bytes32(bytes4(data));
    }
}
