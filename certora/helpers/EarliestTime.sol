// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";
import "../../src/interfaces/IVaultV2.sol";

contract EarliestTime {
    VaultV2 public vault;
    uint256 public lastExecutableAt;
    bytes4 public lastSelector;

    function getSelector(bytes memory data) public pure returns (bytes4) {
        require(data.length >= 4, "Data too short");
        return bytes4(data);
    }

    function extractDecreaseTimelockArgs(bytes memory data)
        public
        pure
        returns (bytes4 targetSelector, uint256 newTimelock)
    {
        require(data.length >= 68, "Invalid decreaseTimelock data");
        bytes4 selector = bytes4(data);
        require(selector == IVaultV2.decreaseTimelock.selector, "Not decreaseTimelock");

        bytes memory params = new bytes(data.length - 4);
        for (uint256 i = 0; i < params.length; i++) {
            params[i] = data[i + 4];
        }

        (targetSelector, newTimelock) = abi.decode(params, (bytes4, uint256));
    }

    fallback() external {
        lastExecutableAt = vault.executableAt(msg.data);
        lastSelector = bytes4(msg.data);
    }
}
