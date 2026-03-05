// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";

/// @dev Harness that captures executableAt[msg.data] via its fallback.
/// When called with the same calldataarg as decreaseTimelock, msg.data matches the
/// decreaseTimelock calldata, so vault.executableAt(msg.data) returns the pending
/// operation's executable-at timestamp.
contract DecreaseTimelockChecker {
    VaultV2 public vault;

    uint256 public lastExecAt;

    fallback() external payable {
        lastExecAt = vault.executableAt(msg.data);
    }
}
