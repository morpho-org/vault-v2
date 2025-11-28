// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";
import "../../src/interfaces/IVaultV2.sol";

contract EarliestTime {
    VaultV2 public vault;

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
        bytes4 selector = bytes4(msg.data);
        require(!vault.abdicated(selector), "Function is abdicated");

        uint256 currentTime = block.timestamp;
        uint256 currentTimelockValue = vault.timelock(selector);
        require(currentTime + currentTimelockValue < type(uint256).max, "Overflow");
        uint256 time1 = currentTime + currentTimelockValue;

        uint256 alreadySubmittedTime = vault.executableAt(msg.data);
        uint256 time2 = alreadySubmittedTime == 0 ? type(uint256).max : alreadySubmittedTime;

        uint256 minTime = time1 < time2 ? time1 : time2;
        require(currentTime < minTime, "Not before minimum time");
    }
}
