// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {VaultV2} from "../../src/VaultV2.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";

contract EarliestTime {
    VaultV2 public vault;

    // Hash and executableAt of the calldata of the last fallback call.
    bytes32 public lastHash;
    uint256 public lastExecutableAt;

    /// @dev Returns the selector whose timelock applies to the submission of data, see VaultV2.submit.
    /// @dev Reverts on data too short to be executed, which excludes it from the rules.
    function timelockSelector(bytes calldata data) external pure returns (bytes4) {
        // forge-lint: disable-next-item(custom-errors) ack.
        require(data.length >= 4, "Data too short");
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(data);
        if (selector != IVaultV2.decreaseTimelock.selector) return selector;
        // forge-lint: disable-next-item(custom-errors) ack.
        require(data.length >= 68, "Data too short");
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the second bytes4.
        return bytes4(data[4:8]);
    }

    function hash(bytes calldata data) external pure returns (bytes32) {
        return keccak256(data);
    }

    /// @dev Returns (true, selector, newDuration) iff data can be executed as decreaseTimelock(selector, newDuration), up to the check on newDuration.
    /// @dev Shorter data reverts at execution (calldata too short to decode the arguments), and so does decreaseTimelock(decreaseTimelock, _).
    function decreaseTimelockArgs(bytes calldata data)
        external
        pure
        returns (bool isDecreaseTimelock, bytes4 selector, uint256 newDuration)
    {
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        if (data.length < 68 || bytes4(data) != IVaultV2.decreaseTimelock.selector) return (false, 0, 0);
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the second bytes4.
        selector = bytes4(data[4:8]);
        if (selector == IVaultV2.decreaseTimelock.selector) return (false, 0, 0);
        return (true, selector, uint256(bytes32(data[8:40])));
    }

    /// @dev Called with the calldata of a call to the vault, records what this call reads and writes in executableAt.
    /// @dev Only the hash and the executableAt of the calldata are reliable: the prover does not constrain its content to the arguments of the call.
    fallback() external {
        lastHash = keccak256(msg.data);
        lastExecutableAt = vault.executableAt(msg.data);
    }
}
